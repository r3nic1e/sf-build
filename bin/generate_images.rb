#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'optparse'
require 'yaml'
require 'etc'
require 'socket'
require 'fileutils'
require 'erb'
require 'json'
require 'pp'

require 'aptly'
require 'docker_helper'
require 'debuild'
require 'git_helper'

require_relative 'build'

ROOT_PATH = File.realpath File.expand_path('../../', __FILE__)
DISTRIBUTIONS = %w[precise trusty xenial].freeze

UBUNTU_BASE_IMAGE = 'ubuntu'.freeze

class Hash
  def stringify_keys
    result = transform_keys(&:to_s)
    result.each_pair do |key, value|
      result[key] = value.stringify_keys if value.is_a? Hash
    end
    result
  end

  def transform_keys
    return enum_for(:transform_keys) unless block_given?
    result = self.class.new
    each_key do |key|
      result[yield(key)] = self[key]
    end
    result
  end
end

# @return [Array]
def get_distributions
  DISTRIBUTIONS
end

# @return [Hash]
def get_args
  options = {
    release: false,
    skip_push: false,
    skip_pull: false,
    distributions: get_distributions,
    username: nil,
  }
  OptionParser.new do |parser|
    parser.on '--[no-]release', 'Generate release images' do |v|
      options[:release] = v
    end
    parser.on '--[no-]skip-push', 'Skip pushing release images to registry' do |v|
      options[:skip_push] = v
    end
    parser.on '--[no-]skip-pull', 'Skip pulling release images from registry' do |v|
      options[:skip_pull] = v
    end
    parser.on '-dNAME', '--distribution=NAME', 'Generate images only for the following distributions', get_distributions do |v|
      if options[:distributions] == get_distributions
        options[:distributions] = [v]
      else
        options[:distributions] << v
      end
    end
    parser.on '-uNAME', '--username=NAME', 'Set username for repo creation' do |v|
      options[:username] = v
    end
    parser.on '-h', '--help' do
      puts parser
      exit
    end
  end.parse! ARGV
  options
end

# @param [String] username
# @param [Boolean] use_release_images
def create_devel_config(username: nil, use_release_images: false)
  base_config = {
    aptly: {
      repo: 'dev-',
      snapshot_prefix: 'repo-dev-',
      merge_prefix: 'dev-',
      force_replace: 1
    },
    image: {}
  }

  base_config[:image][:name] = 'sf-build' unless use_release_images

  unless username
    username = Etc.getlogin
    if %w[root ubuntu].include? username
      hostname = Socket.gethostname
      tokens = hostname.split '-'
      username = tokens[1] if tokens[0] == 'vm'
    end

    print "Enter username (#{username}): "
    answer = gets.chomp
    username = answer if answer
  end

  %i[repo snapshot_prefix merge_prefix].each { |key| base_config[:aptly][key] += username }

  File.open 'devel.yml', 'w' do |f|
    f.write YAML.dump base_config.stringify_keys
  end
end

# @param [Debuild] debuild
# @param [String] distribution
# @param [Array] templates
# @param [Array] dockerfiles
# @return [Array]
def build_images(debuild:, distribution:, templates:, dockerfiles:)
  templates_path = File.join ROOT_PATH, 'docker', 'templates'
  distribution_path = File.join ROOT_PATH, 'docker', 'distributions', distribution

  FileUtils.mkdir_p distribution_path unless Dir.exist? distribution_path

  exclude_list = templates.map { |t| t[:src] }.flatten

  Dir.open(templates_path).each do |name|
    next if exclude_list.include? name
    next if %w[. ..].include? name
    FileUtils.cp File.join(templates_path, name), File.join(distribution_path, name)
  end

  templates.each do |template|
    template_path = File.join templates_path, template[:src]
    renderer = nil
    File.open template_path do |f|
      renderer = ERB.new f.read
    end

    b = binding
    template[:context].each do |name, value|
      b.local_variable_set name, value
    end
    template_contents = renderer.result b

    destination_path = File.join distribution_path, template[:dst]
    File.open destination_path, 'w' do |f|
      f.write template_contents
    end
  end

  # copy Gemfiles
  %w[Gemfile Gemfile.lock].each do |name|
    FileUtils.cp File.join(ROOT_PATH, name), File.join(distribution_path, name)
  end

  images = []

  dockerfiles.each do |dockerfile|
    tag = "#{debuild.config.image_name}#{dockerfile[:suffix]}:#{distribution}"

    Docker.options = { read_timeout: 900 }

    image = Docker::Image.build_from_dir distribution_path, dockerfile: dockerfile[:src], t: tag do |chunk|
      begin
        info = JSON.parse! chunk
        if info.key? 'stream'
          puts info['stream']
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

    images << image
  end

  images
end

# @param [Debuild] debuild
# @param [String] distribution
# @param [String] repo
def build_dummy_package(debuild:, distribution:, repo:)
  aptly = Aptly.new debuild.config.aptly_api_url
  packages = aptly.repo_search_package repo: repo

  puts "DEBUG: repo #{repo} has #{packages.length} packages"

  unless packages.empty?
    debuild.publish_repo repo: repo, distribution: distribution
    debuild.update_repo repo: repo, distribution: distribution
    return
  end

  puts 'Build dummy package to initialize repository'

  debuild.skip_depends_image = true

  debuild.main(
    package: 'dummy',
    distribution: distribution,
    verbose: false,
    skip_apt_update: true
  )

  debuild.publish_repo repo: repo, distribution: distribution
  debuild.update_repo repo: repo, distribution: distribution

  puts 'Finished'
end

# @param [Debuild] debuild
# @param [Array] distributions
# @param [String] username
# @param [Boolean] from_scratch
def build_devel_images(debuild:, distributions:, username: nil, from_scratch: false)
  create_devel_config username: username

  debuild.read_settings image_suffix: nil

  distributions.each do |distribution|
    repo = debuild.create_repo prefix: debuild.config.aptly_repo, distribution: distribution
    debuild.publish_repo repo: repo, distribution: distribution

    apt_sources = []

    # release apt repo
    apt_sources << {
      repo: "#{debuild.config.aptly_repo(release: true)}-#{distribution}",
      distribution: distribution,
      repo_url: debuild.config.aptly_repo_url(release: true)
    }

    # devel apt repo
    apt_sources << {
      repo: repo,
      distribution: distribution,
      repo_url: debuild.config.aptly_repo_url
    }

    apt_sources_context = {
      apt_sources: apt_sources
    }

    dockerfile_context = {
      image_name: (from_scratch ? UBUNTU_BASE_IMAGE : debuild.config.image_name(release: true)),
      image_tag: distribution,
      apt_sources: 'devel.list',
      repo_url: debuild.config.aptly_repo_url
    }

    pull_images images: [
      "#{dockerfile_context[:image_name]}:#{dockerfile_context[:image_tag]}"
    ]

    templates = [
      { src: 'aptly.list', dst: 'devel.list', context: apt_sources_context },
      { src: 'aptly.list', dst: 'test.list', context: apt_sources_context },
      {
        src: (from_scratch ? 'Dockerfile' : 'Dockerfile.devel'),
        dst: 'Dockerfile.devel',
        context: dockerfile_context
      },
      {
        src: 'Dockerfile.test',
        dst: 'Dockerfile.test',
        context: dockerfile_context.merge(image_name: UBUNTU_BASE_IMAGE)
      }
    ]

    dockerfiles = [
      { src: 'Dockerfile.devel', suffix: '-devel' },
      { src: 'Dockerfile.test', suffix: '-test' }
    ]

    build_images(
      debuild: debuild,
      distribution: distribution,
      templates: templates,
      dockerfiles: dockerfiles
    )

    # dirty hack to use correct local images for dummy package build
    # here we add '-devel' suffix to base image name
    debuild.read_settings

    build_dummy_package(
      debuild: debuild,
      distribution: distribution,
      repo: repo
    )

    # dirty hack to reset setting
    # here we skip adding any suffix to base image name
    # because this suffix is added during image build
    debuild.read_settings image_suffix: nil
  end
end

# @param [Debuild] debuild
# @param [Array] distributions
# @param [Boolean] push
def build_release_images(debuild:, distributions:, push: false)
  debuild.read_settings

  distributions.each do |distribution|
    repo = debuild.create_repo prefix: debuild.config.aptly_repo, distribution: distribution
    debuild.publish_repo repo: repo, distribution: distribution

    apt_sources = []

    # release apt repo
    apt_sources << {
      repo: repo,
      distribution: distribution,
      repo_url: debuild.config.aptly_repo_url
    }

    apt_sources_context = {
      apt_sources: apt_sources
    }

    dockerfile_context = {
      image_name: UBUNTU_BASE_IMAGE,
      image_tag: distribution,
      apt_sources: 'release.list',
      repo_url: debuild.config.aptly_repo_url
    }

    pull_images images: [
      "#{dockerfile_context[:image_name]}:#{dockerfile_context[:image_tag]}"
    ]

    templates = [
      { src: 'aptly.list', dst: 'release.list', context: apt_sources_context },
      { src: 'Dockerfile', dst: 'Dockerfile.release', context: dockerfile_context }
    ]

    dockerfiles = [
      { src: 'Dockerfile.release', suffix: '' }
    ]

    images = build_images(
      debuild: debuild,
      distribution: distribution,
      templates: templates,
      dockerfiles: dockerfiles
    )

    push_images images: images if push

    build_dummy_package(
      debuild: debuild,
      distribution: distribution,
      repo: repo
    )
  end
end

# @param [Debuild] debuild
# @param [Array] distributions
def pull_release_images(debuild:, distributions:)
  debuild.read_settings skip_devel: true

  image_name = debuild.config.image_name release: true
  images = distributions.map { |d| "#{image_name}:#{d}" }

  pull_images images: images
end

# @param [Debuild] debuild
def remove_depends_images(debuild:)
  puts 'Removing depends images:'

  containers = Docker::Container.all(all: true)

  Docker::Image.all.each do |image|
    repotags = image.info['RepoTags']
    next unless repotags

    repotags.each do |repotag|
      repo, tag = repotag.split ':'
      next unless repo.start_with?(debuild.config.image_name) && (repo['-depends-'] || repo['-inspect-'])
      containers.each do |container|
        container_image = container.info['Image']
        next unless (container_image == repotag) || (container_image == image.info['Id'])

        puts "- removing container #{container.id}"
        container.remove(force: true)
      end

      puts "- removing image #{repotag}"
      image.remove
    end
  end
end

def main
  args = get_args
  if args[:release]
    if ENV['CI_BUILD_REF_NAME']
      raise "Current CI ref is not master (#{ENV['CI_BUILD_REF_NAME']})" unless ENV['CI_BUILD_REF_NAME'] == 'master'

      changes = get_git_changes 'docker/'
      if changes.empty?
        puts 'No changes in dockerfiles, skipping build'
        exit
      end
    else
      #check_git_master_branch
    end

    debuild = Debuild.new release: true

    build_release_images debuild: debuild, distributions: args[:distributions], push: !args[:skip_push]
  else
    debuild = Debuild.new

    pull_release_images debuild: debuild, distributions: args[:distributions] unless args[:skip_pull]
    pull_busybox_image

    build_devel_images debuild: debuild, distributions: args[:distributions], username: args[:username], from_scratch: args[:skip_pull]
  end

  remove_depends_images debuild: debuild
end

if $PROGRAM_NAME == __FILE__
  $stdin.sync = $stdout.sync = $stderr.sync = true

  main
end
