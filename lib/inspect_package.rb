require 'json'
require 'optparse'
require 'pp'
require 'set'
require 'etc'

require_relative 'debuild'
require_relative 'aptly'
require_relative 'docker_helper'

# Base package class
class SFPackage
  attr_reader :build_depends, :name, :build_depends_cache_key, :version

  def initialize(name)
    # dirty hack to deal with kernel packages
    name = Regexp.last_match(1) if name =~ /^(kernel\d+(?:-acl)?)-[a-z]+-\d+/

    @name = name
    @version = @recipe = @build_depends = @uploaded_versions = @build_depends_cache_key = nil
  end

  def has_recipe?
    @recipe && @recipe.is_a?(Hash)
  end

  def recipe=(recipe)
    @recipe = recipe
    _on_recipe_updated!
  end

  def has_uploaded_versions?
    @uploaded_versions.is_a? Array
  end

  def uploaded_versions=(package_versions)
    @uploaded_versions = []

    package_versions.each do |item|
      tokens = item.split
      # TODO: fix prefix
      prefix = ''
      version = if tokens.length == 1
                  tokens[0]
                elsif tokens.length == 2
                  tokens[1] if (tokens[0] == "#{prefix}#{@name}") || (tokens[0] == 'Version:')
                elsif (tokens.length == 4) && (tokens[1] == "#{prefix}#{@name}")
                  tokens[2]
                end

      @uploaded_versions << version if version
    end
  end

  def uploaded?
    @uploaded_versions.include? @version
  end

  def has_distribution?(distribution)
    @recipe['ubuntu_distribution'].include? distribution
  end

  private

  def _on_recipe_updated!
    _update_version!
    _update_build_depends!
    _update_build_depends_cache_key!
  end

  def _update_build_depends_cache_key!
    cache_key = @recipe['build_depends_cache_key']
    @build_depends_cache_key = (cache_key ? cache_key : @name).downcase
  end

  def _update_build_depends!
    @build_depends = []
    return unless @recipe.key? 'build_depends'
    @recipe['build_depends'].each do |item|
      name = item.split('=')[0]
      # TODO: fix prefix
      prefix = ''
      next unless name.start_with? prefix

      package = SFPackage.new name.gsub(prefix, '')
      @build_depends << package
    end
  end

  def _update_version!
    version = @recipe['version']
    revision = @recipe['revision']

    @version = (revision ? "#{version}-#{revision}" : version)
  end
end

class PackageRepository
  attr_reader :distribution

  # @param [String] distribution
  # @param [Debuild] debuild_module
  def initialize(distribution, debuild_module)
    @repository = {}
    @distribution = distribution
    @debuild_module = debuild_module

    @containers = []

    @aptly_repo = _get_aptly_repo
    @inspect_image = _prepare_inspect_image
    @inspect_container = _prepare_inspect_container
  end

  # @param [String] package_name
  # @return [SFPackage]
  def [](package_name)
    self.<< package_name unless @repository.include? package_name
    @repository[package_name]
  end

  # @param [String] package_name
  def <<(package_name)
    package = (@repository.key?(package_name) ? @repository[package_name] : SFPackage.new(package_name))

    load_package_recipe(package) unless package.has_recipe?
    return unless package.has_recipe?
    search_package_uploads(package) unless package.has_uploaded_versions?

    @repository[package.name] = package
  end

  # @param [SFPackage] package
  def search_package_uploads(package)
    # TODO: fix prefix
    prefix = ''
    apt_command = "apt-cache show #{prefix}#{package.name}".split

    puts "DEBUG: apt-cache show '#{prefix}#{package.name}' (#{Thread.current})"
    stdout, stderr, rcode = @inspect_container.exec(apt_command)

    if (rcode != 0) && (rcode != 100)
      puts "DEBUG: rcode #{rcode}, stderr: #{stderr}"
      puts 'Error while searching package in apt'
      exit 1
    end

    package_version = stdout.join.lines.map(&:chomp).grep(/Version:/)
    package.uploaded_versions = package_version
  end

  # @param [SFPackage] package
  def load_package_recipe(package)
    recipe_file = File.join package.name, 'recipe.rb'
    unless File.exist? File.join('recipes', recipe_file)
      puts "DEBUG: recipe #{recipe_file} not found"
      return
    end
    inspect_command = "fpm-cook inspect #{recipe_file}".split

    puts "DEBUG: fpm-cook inspect '#{package.name}' (#{Thread.current})"
    stdout, stderr, rcode = @inspect_container.exec(inspect_command)

    if rcode != 0
      puts "DEBUG: rcode #{rcode}, stderr: #{stderr}"
      puts 'Error while inspecting package'
      exit 1
    end

    package.recipe = JSON.parse stdout.join
  end

  def cleanup_containers
    @containers.each { |container| container.remove(force: true) }
    @inspect_image.remove
  end

  private

  # @return [String]
  def _get_aptly_repo
    @debuild_module.read_settings unless @debuild_module.config.settings

    "#{@debuild_module.config.aptly_repo}-#{@distribution}"
  end

  # @return [Docker::Image]
  def _prepare_inspect_image
    image_name = @debuild_module.config.image_name
    image_tag = @distribution
    image_repotag = "#{image_name}:#{image_tag}"

    inspect_image_name = "#{image_name}-inspect-#{@debuild_module.config.timestamp}"
    inspect_image_repotag = "#{inspect_image_name}:#{image_tag}"

    inspect_container_name = "#{@debuild_module.config.container}-#{image_tag}-#{@debuild_module.config.timestamp}"

    puts "DEBUG: inspect_image_repotag   => #{inspect_image_repotag}"
    puts "DEBUG: inspect_container_name  => #{inspect_container_name}"

    command = %w[chmod 755 /bin /lib /recipes]

    inspect_environment = {
      SKIP_UPDATE: 0,
      APT_SOURCES: @debuild_module.config.apt_sources(@distribution).join("\n")
    }

    inspect_container = create_docker_container(
      'name' => inspect_container_name,
      image: image_repotag,
      env: inspect_environment.to_a.map { |a| "#{a[0]}=#{a[1]}" },
      tty: true,
      cmd: command
    )
    puts "Created seed inspect container: #{inspect_container}"

    @debuild_module.inject_recipes_to_container container: inspect_container

    puts "Starting seed inspect container #{inspect_container_name}"
    inspect_container.start

    puts "Waiting seed inspect container #{inspect_container_name} to exit"
    return_code = inspect_container.wait['StatusCode']
    if return_code != 0
      puts "Return code #{return_code}, not removing seed inspect container #{inspect_container_name}"
      puts 'See logs below:'
      puts inspect_container.logs(stdout: true, stderr: true)

      exit return_code
    end

    inspect_image = inspect_container.commit repo: inspect_image_name, tag: image_tag
    inspect_container.remove

    inspect_image
  end

  # @param [String] command
  # @return [Docker::Container]
  def _prepare_inspect_container(command: nil)
    inspect_environment = {
      SKIP_DEBUG: 1,
      SKIP_UPDATE: 1
    }

    inspect_container_name = "#{@debuild_module.config.container}-#{@distribution}-#{Time.now.to_i}"
    command = %w[sleep infinity] if command.nil?

    inspect_container = create_docker_container(
      'name' => inspect_container_name,
      image: @inspect_image.id,
      env: inspect_environment.to_a.map { |a| "#{a[0]}=#{a[1]}" },
      tty: true,
      entrypoint: command,
      WorkingDir: '/recipes'
    )

    inspect_container.start

    @containers << inspect_container
    inspect_container
  end
end

class PackageQueue
  attr_reader :queue

  # @param [PackageRepository] repository
  def initialize(repository)
    @repository = repository
    @force_build = false

    @queue = []

    # threading
    @threads = []
    @inspected = Set.new
    @inspect_queue = Queue.new
    @mutex = Mutex.new
  end

  # @param [Array] package_names
  # @param [Boolean] force_build
  def make(package_names, force_build: false)
    @force_build = force_build

    start = Time.now

    package_names.each { |package_name| @inspect_queue.push package_name }

    @threads = Array.new(Etc.nprocessors + 1) do
      Thread.new do
        until @inspect_queue.empty?
          package_name = @inspect_queue.pop

          inspected = false
          @mutex.synchronize do
            inspected = @inspected.include? package_name
            @inspected << package_name unless inspected
          end

          unless inspected
            package = @repository[package_name]
            next if package.nil?
            package.build_depends.each { |dependency| @inspect_queue.push dependency.name }
          end
        end
      end
    end

    @threads.each(&:join)

    package_names.each { |package_name| self.<< package_name }

    finish = Time.now

    puts "DEBUG: time to inspect all packages #{finish - start}"
  end

  # @param [String] package_name
  def <<(package_name)
    package = @repository[package_name]
    return if package.nil?
    package.build_depends.each { |dependency| self.<< dependency.name }

    return if @queue.include? package.name

    if @force_build
      @queue << package.name
      return
    end

    unless package.has_distribution? @repository.distribution
      puts "SKIP: package '#{package.name} #{package.version}' does not have matching 'ubuntu_distribution' property (#{@repository.distribution})"
      return
    end

    if package.uploaded?
      puts "SKIP: package '#{package.name} #{package.version}' is already uploaded to the repo"
      return
    end

    @queue << package.name
  end
end

# @param [Array] packages
# @param [String] distribution
# @param [Debuild] debuild
# @param [Boolean] force_build
# @return [Array]
def make_build_queue(packages, distribution, debuild, force_build: false)
  package_repository = PackageRepository.new distribution, debuild
  package_queue = PackageQueue.new package_repository

  package_queue.make packages, force_build: force_build
  package_repository.cleanup_containers

  puts 'DEBUG: final queue'
  pp package_queue.queue

  package_queue.queue.map { |package_name| package_repository[package_name] }
end

def get_args
  options = {
    release: false
  }
  OptionParser.new do |parser|
    parser.on '-d', '--distribution=NAME', :REQUIRED, 'Ubuntu distribution' do |v|
      options[:distribution] = v
    end
    parser.on '--[no-]release', 'Release mode' do |v|
      options[:release] = v
    end
    parser.on '-h', '--help' do
      puts parser
      exit
    end
  end.parse! ARGV
  options[:packages] = ARGV

  exit 1 unless options[:distribution]
  exit 1 if options[:packages].empty?
  options
end

def main
  $stdin.sync = true
  $stdout.sync = true

  args = get_args
  debuild = Debuild.new release: args[:release]
  debuild.read_settings
  make_build_queue args[:packages], args[:distribution], debuild, force_build: true
end

main if $PROGRAM_NAME == __FILE__
