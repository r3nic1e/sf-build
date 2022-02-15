require 'singleton'
require 'fileutils'
require 'docker'
require_relative '../docker_helper'
require_relative 'config'

# Main class containing build logic
class Debuild
  # Singleton class to contain some runtime variables
  #
  # @!attribute [rw] distribution
  #   @return [String]
  # @!attribute [rw] skip_apt_update
  #   @return [Boolean]
  # @!attribute [rw] skip_package_build
  #   @return [Boolean]
  # @!attribute [rw] skip_package_upload
  #   @return [Boolean]
  # @!attribute [rw] skip_package_inspect
  #   @return [Boolean]
  # @!attribute [rw] use_existing_depends_image
  #   @return [Boolean]
  # @!attribute [rw] force_package_build
  #   @return [Boolean]
  # @!attribute [rw] command
  #   @return [String]
  # @!attribute [rw] release
  #   @return [Boolean]
  # @!attribute [rw] use_release_images
  #   @return [Boolean]
  # @!attribute [rw] verbose
  #   @return [Boolean]
  # @!attribute [rw] skip_available_packages
  #   @return [Boolean]
  class Settings
    include Singleton
    attr_accessor :distribution, :skip_apt_update, :skip_package_build, :skip_package_upload, :skip_package_inspect,
                  :use_existing_depends_image, :force_package_build, :command, :release, :use_release_images, :verbose,
                  :skip_available_packages

    def initialize
      @distribution = 'bionic'
    end
  end

  # @return [Boolean]
  attr_accessor :skip_depends_image

  # Return settings singleton
  #
  # @return [Settings]
  def settings
    Settings.instance
  end

  # @param [Boolean] skip_depends_image
  # @todo move to settings
  def initialize(skip_depends_image: false)
    docker_login

    @skip_depends_image = skip_depends_image
  end

  # Clean directory with built packages
  def clean_deb
    deb_path = File.join @config.output, settings.distribution

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

  # Build package
  #
  # @param [String|SFPackage] package
  def build_deb(package:)
    skip_apt_update = settings.skip_apt_update
    package_name = if package.is_a? SFPackage
                     package.name
                   else
                     package
                   end

    image_name = @config.image_name
    image_tag = settings.distribution
    image_repotag = "#{image_name}:#{image_tag}"

    check_build_images image_repotag: image_tag

    data_container = create_data_container image_tag: image_tag

    if @skip_depends_image
      build_image_repotag = image_repotag
      install_build_depends = true
    else
      build_image_repotag = create_depends_image(
        image_repotag: image_repotag,
        image_tag: image_tag,
        package: package,
        skip_apt_update: skip_apt_update,
      )
      # avoid double apt-update runs
      skip_apt_update = true
      install_build_depends = false
    end

    build_container, build_container_name, command = create_build_container(
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
    )

    extract_deb_files(build_container: build_container)

    puts "Removing build container #{build_container_name}"
    build_container.remove

    puts 'BUILD FINISHED'
  end

  # Run build container and collect logs
  #
  # @param [Docker::Container] build_container
  # @param [String] build_container_name
  # @param [String] command
  def run_build(build_container:, build_container_name:, command:)
    puts "DEBUG: will run the following command in build container #{build_container_name}"
    puts "DEBUG: #{command}"

    puts "Starting build container #{build_container_name}"
    build_container.start

    build_container.attach(tty: true) { |chunk| print chunk } if settings.verbose

    puts "Waiting build container #{build_container_name} to exit"
    return_code = build_container.wait['StatusCode']
    return if return_code.zero?

    puts "Return code #{return_code}, not removing build container #{build_container_name}"
    unless settings.verbose
      puts 'See logs below:'
      puts build_container.logs(stdout: true, stderr: true)
    end

    exit return_code
  end

  # Get valid for build images
  # @param [String] image_repotag
  # @raise [RuntimeError] if build image not found
  def check_build_images(image_repotag:)
    images = Docker::Image.all
    valid_images = []
    images.each do |image|
      repotags = image.info['RepoTags']
      next unless repotags
      valid_images << image if repotags.include? image_repotag
    end

    raise RuntimeError("Build image #{image_repotag} not found") unless valid_images
  end

  # Extract built packages from build container
  #
  # @param [Docker::Container] build_container
  def extract_deb_files(build_container:)
    deb_path = File.join @config.output, settings.distribution
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

  # Inject some folders into container
  # Currently these folders are injected:
  #   * recipes dir
  #   * '/bin'
  #   * '/lib'
  #
  # @param [Docker::Container] container
  def inject_recipes_to_container(container:)
    packages_dir = File.join Dir.pwd, 'recipes'
    bin_dir = File.join Dir.pwd, 'bin'
    lib_dir = File.join Dir.pwd, 'lib'
    netrc = File.join Dir.home, '.netrc'

    dirs = {
      packages_dir => '/recipes',
      bin_dir => '/usr/local/bin',
      lib_dir => '/usr/local/lib',
      netrc => '/root/.netrc',
    }

    dirs.each do |srcdir, dstdir|
      tar_stream = create_tar srcdir, prefix = dstdir
      container.archive_in_stream('/') { tar_stream.read }
    end
  end

  # Create build container
  #
  # @param [DOcker::Container] data_container
  # @param [String] image_repotag
  # @param [String] image_tag
  # @param [String] package_name
  # @option args [Boolean] :skip_apt_update
  # @option args [Bool] :install_build_depends
  # @return [Array]
  def create_build_container(data_container:, image_repotag:, image_tag:, package_name:, **args)
    skip_apt_update = args[:skip_apt_update]
    install_build_depends = args[:install_build_depends]

    if install_build_depends
      default_command = %w[/usr/local/bin/fpm-cook package --install-build-depends --tmp-root=/build --cache-dir=/sources --pkg-dir=/deb --color]
    else
      default_command = %w[/usr/local/bin/fpm-cook package --tmp-root=/build --cache-dir=/sources --pkg-dir=/deb --color]
    end

    puts 'DEBUG: default command to run in build container'
    puts "DEBUG: #{default_command}"

    command = settings.command.nil? ? default_command : ['bash', '-c', settings.command]

    build_environment = {
      SKIP_UPDATE: (skip_apt_update ? 1 : 0),
      APT_SOURCES: @config.apt_sources.join("\n"),
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

  # Create image with preinstalled depends packages
  #
  # @param [String] image_repotag
  # @param [String] image_tag
  # @param [String] package
  # @param [Boolean] skip_apt_update
  # @return [String]
  def create_depends_image(image_repotag:, image_tag:, package:, skip_apt_update:)
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

    if settings.use_existing_depends_image
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

    default_command = %w[/usr/local/bin/fpm-cook install-build-deps --color]

    puts 'DEBUG: default command to run in depends container'
    puts "DEBUG: #{default_command}"

    command = default_command

    depends_environment = {
      SKIP_UPDATE: (skip_apt_update ? 1 : 0),
      APT_SOURCES: @config.apt_sources.join("\n"),
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

    depends_container.attach(tty: true) { |chunk| print chunk } if settings.verbose

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

  # Creates data container
  # It is used for caching packages sources
  #
  # @param [String] image_tag
  # @return [Docker::Container]
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

  # Run testing container and print package information
  #
  # @param [String] package_name
  # @param [String] command
  def test_deb(package_name:, command: nil)
    image_name = @config.image_name
    image_tag = settings.distribution
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
      APT_SOURCES: @config.apt_sources.join("\n")
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
      unless settings.verbose
        puts 'See logs below:'
        puts test_container.logs(stdout: true, stderr: true)
      end

      exit return_code
    end

    puts 'Removing test container'
    test_container.remove
  end

  # Test build package
  # @param [String] package_name
  # @param [Boolean] skip_available_packages
  # @param [String] command
  def test(package_name:, skip_available_packages: false, command: nil)
    available_packages = packages

    puts "DEBUG: #{package_name}"
    puts "DEBUG: #{available_packages.include? package_name}"

    unless skip_available_packages || available_packages.include?(package_name)
      puts "Unknown package #{package_name}, use one of these: #{available_packages.sort}"
      exit 1
    end

    # @todo fix prefix
    prefix = ''
    package_name = "#{prefix}#{package_name}"

    test_deb package_name: package_name, command: command
  end

  # Build package and upload it to aptly
  # @param [String|SFPackage] package
  def main(package:)
    package_name = if package.is_a? SFPackage
                     package.name
                   else
                     package
                   end

    @config.update_timestamp
    clean_deb
    available_packages = @config.packages

    unless available_packages.include? package_name
      puts "Unknown package #{package_name}, use one of these: #{available_packages}"
      exit 1
    end

    unless settings.skip_package_build
      clean_deb
      build_deb package: package
    end

    update_aptly
  end

  # Upload built package to aptly and refresh aptly repository
  def update_aptly
    distribution = settings.distribution
    puts "Distribution: #{distribution}"
    puts 'DEBUG: @config.settings'
    pp @config.settings

    deb_path = File.join @config.output, distribution
    deb_abs_path = File.absolute_path deb_path

    repo = "#{@config.aptly_repo}-#{distribution}"

    begin
      result = @aptly.repo_create name: repo, default_distribution: distribution
      puts "Repo #{repo} created"
      puts result
    rescue Aptly::ExistsError
      puts "Repo #{repo} already exists"
    end

    upload_deb directory: deb_abs_path, repo: repo unless settings.skip_package_upload
    update_repo repo: repo

    puts 'Done'
  end

  # Pull build docker images
  def pull_build_images
    image_name = @config.image_name
    image_repotag = "#{image_name}:#{settings.distribution}"

    puts "Pulling build image: #{image_repotag}"
    Docker::Image.create 'fromImage' => image_repotag

    puts 'Pulling busybox image'
    pull_busybox_image
  end
end
