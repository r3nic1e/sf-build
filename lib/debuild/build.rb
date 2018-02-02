require 'fileutils'
require 'docker'
require_relative '../docker_helper'

class Debuild
  attr_accessor :skip_depends_image

  def initialize(release: false, use_release_images: false, skip_depends_image: false)
    docker_login

    if release
      require_relative 'release'
    else
      require_relative 'devel'
    end

    @use_release_images = use_release_images
    @skip_depends_image = skip_depends_image
  end

  def clean_deb(distribution:)
    deb_path = File.join @config.output, distribution

    FileUtils.mkdir_p deb_path unless File.directory? deb_path

    Dir.open(deb_path).each do |f|
      path = File.join deb_path, f

      next unless File.file?(path) && (File.extname(path) == '.deb')

      begin
        FileUtils.rmtree path
      rescue StandardError
        puts "Cannot remove file #{path}"
      end
    end
  end

  def build_deb(package:, distribution:, verbose: false, skip_apt_update: false,
                command: nil, use_existing_depends_image: false)
    package_name = if package.is_a? SFPackage
                     package.name
                   else
                     package
                   end

    image_name = @config.image_name
    image_tag = distribution
    image_repotag = "#{image_name}:#{image_tag}"

    check_build_images image_name: image_name, image_repotag: image_tag

    data_container = create_data_container image_tag: image_tag

    if @skip_depends_image
      build_image_repotag = image_repotag
      install_build_depends = true
    else
      build_image_repotag = create_depends_image(
        command: command,
        image_repotag: image_repotag,
        image_tag: image_tag,
        package: package,
        skip_apt_update: skip_apt_update,
        verbose: verbose,
        use_existing_image: use_existing_depends_image
      )
      # avoid double apt-update runs
      skip_apt_update = true
      install_build_depends = false
    end

    build_container, build_container_name, command = create_build_container(
      command: command,
      data_container: data_container,
      image_repotag: build_image_repotag,
      image_tag: image_tag,
      package_name: package_name,
      skip_apt_update: skip_apt_update,
      install_build_depends: install_build_depends
    )

    inject_recipes_to_container container: build_container

    run_build(
      build_container: build_container,
      build_container_name: build_container_name,
      command: command,
      verbose: verbose
    )

    extract_deb_files(build_container: build_container, distribution: distribution)

    puts "Removing build container #{build_container_name}"
    build_container.remove

    puts 'BUILD FINISHED'
  end

  def run_build(build_container:, build_container_name:, command:, verbose: false)
    puts "DEBUG: will run the following command in build container #{build_container_name}"
    puts "DEBUG: #{command}"

    puts "Starting build container #{build_container_name}"
    build_container.start

    build_container.attach(tty: true) { |chunk| print chunk } if verbose

    puts "Waiting build container #{build_container_name} to exit"
    return_code = build_container.wait['StatusCode']
    return if return_code.zero?

    puts "Return code #{return_code}, not removing build container #{build_container_name}"
    unless verbose
      puts 'See logs below:'
      puts build_container.logs(stdout: true, stderr: true)
    end

    exit return_code
  end

  def check_build_images(image_name:, image_repotag:)
    images = Docker::Image.all
    valid_images = []
    images.each do |image|
      repotags = image.info['RepoTags']
      next unless repotags
      valid_images << image if repotags.include? image_repotag
    end

    raise RuntimeError("Build image #{image_repotag} not found") unless valid_images
  end

  def extract_deb_files(build_container:, distribution:)
    deb_path = File.join @config.output, distribution
    dummy_file = StringIO.new
    build_container.archive_out '/deb' do |stream|
      dummy_file.write stream
    end

    dummy_file.rewind

    Gem::Package::TarReader.new dummy_file do |tar|
      tar.each do |tarfile|
        next unless tarfile.file?
        next unless tarfile.full_name.end_with? '.deb'

        fname = File.basename tarfile.full_name
        File.open File.join(deb_path, fname), 'wb' do |f|
          f.write tarfile.read
        end
      end
    end
    dummy_file.close
  end

  # @param [Docker::Container] container
  def inject_recipes_to_container(container:)
    packages_dir = File.join Dir.pwd, 'recipes'
    ssh_dir = File.join (ENV['HOME'] || '/root'), '.ssh'
    bin_dir = File.join Dir.pwd, 'bin'
    lib_dir = File.join Dir.pwd, 'lib'

    # dirty hacks for gitlab
    if @config.gitlab
      FileUtils.mkpath(ssh_dir, mode: 0o700) unless File.directory? ssh_dir

      ssh_private_key = File.join ssh_dir, 'id_rsa'
      ssh_config = File.join ssh_dir, 'config'

      unless File.file? ssh_private_key
        private_key_contents = ENV['SSH_PRIVATE_KEY']
        File.open(ssh_private_key, 'w') { |f| f.write private_key_contents } if private_key_contents
      end

      FileUtils.cp_r File.join(Dir.pwd, 'docker', 'templates', 'ssh_config'), ssh_config

      File.chmod 0o600, ssh_private_key
      File.chmod 0o600, ssh_config
    end

    dirs = {
      packages_dir => '/recipes',
      ssh_dir => '/.ssh',
      bin_dir => '/bin',
      lib_dir => '/lib'
    }

    dirs.each do |srcdir, dstdir|
      tar_stream = create_tar srcdir, prefix = dstdir
      container.archive_in_stream('/') { tar_stream.read }
    end
  end

  def create_build_container(command: nil, data_container:, image_repotag:, image_tag:, package_name:,
                             skip_apt_update: false, install_build_depends: false)
    if install_build_depends
      default_command = %w[/bin/fpm-cook package --install-build-depends --tmp-root=/build --cache-dir=/sources --pkg-dir=/deb --color]
    else
      default_command = %w[/bin/fpm-cook package --tmp-root=/build --cache-dir=/sources --pkg-dir=/deb --color]
    end

    puts 'DEBUG: default command to run in build container'
    puts "DEBUG: #{default_command}"

    command = if command.nil?
                default_command
              else
                ['bash', '-c', command]
              end

    build_environment = {
      SKIP_UPDATE: (skip_apt_update ? 1 : 0),
      APT_SOURCES: @config.apt_sources(image_tag).join("\n"),
      PACKAGE_DIR: File.join('/recipes', package_name)
    }

    build_container_name = "#{@config.container}-#{image_tag}-#{@config.timestamp}"
    build_container = create_docker_container(
      'name' => build_container_name,
      image: image_repotag,
      env: build_environment.to_a.map { |a| "#{a[0]}=#{a[1]}" },
      tty: true,
      cmd: command,
      HostConfig: {
        VolumesFrom: [data_container.id]
      }
    )
    puts "Created build container: #{build_container_name}"
    [build_container, build_container_name, command]
  end

  def create_depends_image(command: nil,
                           image_repotag:, image_tag:, package:,
                           skip_apt_update: false, verbose: false, use_existing_image: false)
    image_name = image_repotag.split(':')[0]
    package_name = if package.is_a? SFPackage
                     package.name
                   else
                     package
                   end

    depends_cache_key = if package.is_a? SFPackage
                          package.build_depends_cache_key
                        else
                          package_name
                        end
    depends_image_name = "#{image_name}-depends-#{depends_cache_key}"
    depends_image_repotag = "#{depends_image_name}:#{image_tag}"

    if use_existing_image
      found = false
      Docker::Image.all.each do |image|
        repotags = image.info['RepoTags']
        next unless repotags

        if repotags.include? depends_image_repotag
          found = true
          break
        end
      end

      unless found
        puts "Unable to find existing image #{depends_image_repotag}, aborting"
        exit 1
      end

      puts "DEBUG: use existing image => #{depends_image_repotag}"
      return depends_image_repotag
    end

    depends_container_name = "#{@config.container}-#{image_tag}-#{@config.timestamp}"
    depends_container_image = image_repotag

    Docker::Image.all.each do |image|
      repotags = image.info['RepoTags']
      next unless repotags

      depends_container_image = depends_image_repotag if repotags.include? depends_image_repotag
    end

    puts "DEBUG: depends_image_repotag   => #{depends_image_repotag}"
    puts "DEBUG: depends_container_name  => #{depends_container_name}"
    puts "DEBUG: depends_container_image => #{depends_container_image}"

    default_command = %w[/bin/fpm-cook install-build-deps --color]

    puts 'DEBUG: default command to run in depends container'
    puts "DEBUG: #{default_command}"

    command = default_command

    depends_environment = {
      SKIP_UPDATE: (skip_apt_update ? 1 : 0),
      APT_SOURCES: @config.apt_sources(image_tag).join("\n"),
      PACKAGE_DIR: File.join('/recipes', package_name)
    }

    depends_container = create_docker_container(
      'name' => depends_container_name,
      image: depends_container_image,
      env: depends_environment.to_a.map { |a| "#{a[0]}=#{a[1]}" },
      tty: true,
      cmd: command
    )
    puts "Created depends container: #{depends_container}"

    inject_recipes_to_container container: depends_container

    puts "Starting depends container #{depends_container_name}"
    depends_container.start

    depends_container.attach(tty: true) { |chunk| print chunk } if verbose

    puts "Waiting depends container #{depends_container_name} to exit"
    return_code = depends_container.wait['StatusCode']
    if return_code != 0
      puts "Return code #{return_code}, not removing depends container #{depends_container_name}"
      puts 'See logs below:'
      puts depends_container.logs(stdout: true, stderr: true)

      exit return_code
    end

    depends_container.commit repo: depends_image_name, tag: image_tag
    depends_container.remove

    depends_image_repotag
  end

  def create_data_container(image_tag:)
    data_container_name = "#{@config.data_container}-#{image_tag}"
    puts "DEBUG: using data_container => #{data_container_name}"

    data_container = Docker::Container.all(all: true).select { |container| container.info['Names'].include? "/#{data_container_name}" }
    if data_container.empty?
      puts "DEBUG: creating data_container => #{data_container_name}"
      data_container = create_docker_container(
        'name' => data_container_name,
        image: 'busybox:latest',
        command: '/bin/true',
        detach: true,
        network_disabled: true,
        volumes: { '/sources' => {}, '/root' => {} }
      )
    else
      data_container = data_container[0]
    end

    data_container
  end

  def test_deb(package_name:, distribution:, verbose: false, command: nil)
    image_name = @config.image_name
    image_tag = distribution
    image_repotag = "#{image_name}:#{image_tag}"

    valid_images = Docker::Image.all.select do |image|
      repotags = image.info['RepoTags']
      repotags && repotags.include?(image_repotag)
    end

    raise RuntimeError("Test image #{image_repotag} not found") unless valid_images

    puts "DEBUG: test image is #{image_repotag}"

    test_command = [
      'apt-get update',
      '&&',
      'apt-get install -y',
      '-o "Dpkg::Options::=--force-confdef"',
      '-o "Dpkg::Options::=--force-confold"',
      '-o "Dpkg::Options::=--force-overwrite"',
      package_name,
      '&&',
      'dpkg-query -L', package_name,
      '&&',
      'dpkg-query -s', package_name
    ]

    test_command << ['&&', "( #{command} )"] unless command.nil?

    final_command = ['bash', '-c', test_command.join(' ')]

    test_environment = {
      SKIP_UPDATE: 0,
      APT_SOURCES: @config.apt_sources(image_tag).join("\n")
    }

    test_container = create_docker_container(
      image: image_repotag,
      cmd: final_command,
      tty: true,
      env: test_environment.to_a.map { |a| "#{a[0]}=#{a[1]}" }
    )

    puts "Created test container: #{test_container}"

    puts 'DEBUG: will run the following command in container'
    puts "DEBUG: #{command}"

    puts 'Starting test container'
    test_container.start

    test_container.attach(tty: true) { |chunk| print chunk } if verbose

    puts
    puts 'Waiting test container to exit'

    return_code = test_container.wait['StatusCode']
    if return_code != 0
      puts "Return code #{return_code}, not removing test container"
      unless verbose
        puts 'See logs below:'
        puts test_container.logs(stdout: true, stderr: true)
      end

      exit return_code
    end

    puts 'Removing test container'
    test_container.remove
  end
end
