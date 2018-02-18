require 'docker'
require 'json'
require 'base64'
require 'pp'

DOCKER_CLIENT_CONFIG = File.join (ENV['HOME'] || '/root'), '.docker', 'config.json'
CONTAINERS = []

module Docker
  class Container
    alias attach_old attach

    def attach(options = {}, excon_params = {}, &block)
      loop do
        begin
          return attach_old(options, excon_params, &block)
        rescue Docker::Error::TimeoutError
          next
        end
      end
    end

    alias wait_old wait

    def wait(time = nil)
      loop do
        begin
          return wait_old(time)
        rescue Docker::Error::TimeoutError
          next
        end
      end
    end
  end
end

# Create docker container with --net=host by default
#
# @param [Hash] opts
# @return [Docker::Container]
def create_docker_container(opts = {})
  opts[:NetworkMode] = 'host' unless opts.include? :NetworkMode
  container = Docker::Container.create opts
  CONTAINERS << container
  container
end

# Forcefully destroy all created containers
# Called on signal trap
#
# @param [Int] signal
def destroy_docker_containers(signal:)
  puts "DEBUG: Got signal #{signal}"
  puts 'DEBUG: have created containers:'
  pp CONTAINERS

  CONTAINERS.each do |container|
    begin
      container.remove force: true
    rescue StandardError
      puts "Failed to remove container #{container}"
    end
  end

  puts 'We are terminated, sorry'
  exit 0
end

# Login to docker registry
# Contains some CI hack
#
# @param [String] registry
# @param [String] default_login
# @param [String] default_email
def docker_login(registry: 'https://index.docker.io/v1/', default_login: '', default_email: '')
  config = (JSON.parse File.read DOCKER_CLIENT_CONFIG if File.exist? DOCKER_CLIENT_CONFIG)

  if config.nil?
    registry = ENV['CI_REGISTRY']
    unless registry
      puts 'Failed to get registry to login to'
      return
    end

    email = default_email
    login = default_login
    password = ENV['CI_BUILD_TOKEN']
  else
    registry_info = config['auths'][registry]
    unless registry_info
      puts "Failed to get auth info from #{DOCKER_CLIENT_CONFIG}"
      return
    end
    auth = registry_info['auth']
    email = registry_info['email'] || default_email
    login, password = Base64.decode64(auth).split ':'
  end
  auth = Docker.authenticate! username: login, password: password, email: email, serveraddress: registry
  puts "DEBUG: docker login [#{auth}]"
end

# Pull dummy busybox image
def pull_busybox_image
  puts 'DEBUG: pulling busybox image'

  creds = Docker.creds
  Docker.creds = '{}'
  Docker::Image.create fromImage: 'busybox:latest'
  Docker.creds = creds
end

# Push docker images to registry
#
# @param [Array<String>] images
def push_images(images:)
  puts images.inspect
  images.each do |image|
    puts "Pushing image #{image}"
    image.push do |chunk|
      begin
        info = JSON.parse chunk
        if info.key? 'progressDetail'
          next
        elsif info.key? 'status'
          puts info['status']
        elsif info.key? 'errorDetail'
          puts "Error building image: #{info['errorDetail']}"
          exit 1
        else
          puts info
        end
      rescue StandardError
        puts info
      end
    end
  end
end

# Pull docker images
#
# @param [Array<String>] images
def pull_images(images:)
  images.each do |image|
    puts "Pulling image #{image}"
    Docker::Image.create fromImage: image
  end
end

# Create tarball from specified directory
#
# @param [String] srcdir
# @param [String] prefix
# @return [StringIO]
def create_tar(srcdir, prefix = '')
  buffer = StringIO.new
  Gem::Package::TarWriter.new(buffer) do |tar|
    Find.find(srcdir) do |path|
      new_path = path.dup
      new_path[srcdir] = prefix
      mode = File.stat(path).mode
      if File.directory? path
        tar.mkdir new_path, mode
      else
        File.open path do |f|
          tar.add_file(new_path, mode) {|tarfile| tarfile.write f.read}
        end
      end
    end
  end
  buffer.rewind
  buffer
end
