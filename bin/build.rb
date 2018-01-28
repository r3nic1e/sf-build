#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'optparse'
require 'git'

require 'debuild'
require 'inspect_package'
require 'git_helper'

# @return [Hash]
def parse_args
  options = {
    distribution: 'precise',
    verbose: false,
    skip_apt_update: false,
    skip_package_build: false,
    skip_package_upload: false,
    skip_package_inspect: false,
    use_existing_depends_image: false,
    force_package_build: false,
    command: nil,
    release: false,
    use_release_images: false
  }
  OptionParser.new do |parser|
    parser.on '-d', '--distribution', %w[natty precise trusty xenial], 'Ubuntu distribution to build for', :REQUIRED do |v|
      options[:distribution] = v
    end
    parser.on '-v', '--[no-]verbose', 'Show build logs' do |v|
      options[:verbose] = v
    end
    parser.on '--[no-]skip-apt-update', "Skip 'apt-get update' before build" do |v|
      options[:skip_apt_update] = v
    end
    parser.on '--[no-]skip-package-build', 'Skip build, only upload package' do |v|
      options[:skip_package_build] = v
    end
    parser.on '--[no-]skip-package-upload', 'Skip upload, only build package' do |v|
      options[:skip_package_upload] = v
    end
    parser.on '--[no-]force-package-build', 'Force package build if already uploaded' do |v|
      options[:force_package_build] = v
    end
    parser.on '--[no-]skip-package-inspect', 'Skip package inspection, ignore build dependencies' do |v|
      options[:skip_package_inspect] = v
    end
    parser.on '--[no-]use-existing-depends-image', 'Use existing build depends image' do |v|
      options[:use_existing_depends_image] = v
    end
    parser.on '--[no-]release', 'Build and push packages to production' do |v|
      options[:release] = v
    end
    parser.on '--[no-]use-release-images', 'Use release images for devel build' do |v|
      options[:use_release_images] = v
    end
    parser.on '--command=NAME', 'Override command running in container' do |v|
      options[:command] = v
    end
    parser.on '-h', '--help' do
      puts parser
      exit
    end
  end.parse! ARGV
  options[:packages] = ARGV.dup
  options
end

def check_git_master_branch
  git = Git.open Dir.pwd
  begin
    git.fetch
  rescue Git::GitExecuteError => e
    puts "Cannot fetch upstream changes: #{e}"
    exit 1
  end

  begin
    branch = git.current_branch
    remote_branch = git.remote.branch branch
    puts "Current branch: #{branch} (#{remote_branch})"

    unless git.diff(branch, remote_branch).size
      puts 'Branch is not synced with upstream'
      exit 1
    end

    unless git.status.reject { |f| f.type.nil? }.empty?
      puts 'There are changes in current branch'
      exit 1
    end
  rescue Git::GitExecuteError
    puts 'Cannot get git status'
    exit 1
  end
end

# @return [Array]
def get_git_packages
  changes = get_git_changes 'recipes/'

  puts "DEBUG: changes=#{changes.inspect}"

  changed_recipes = changes
                    .select { |c| c.start_with? 'recipes/' }
                    .map { |c| c.split('/')[1] }
                    .select { |r| File.directory? File.join('recipes', r) }
                    .select { |r| File.exist? File.join('recipes', r, 'recipe.rb') }

  puts "DEBUG: changed_recipes=#{changed_recipes.inspect}"

  changed_recipes.uniq
end

def main
  args = parse_args
  if ENV['CI_BUILD_REF_NAME']
    build_gitlab_ci args
  elsif args[:release]
    build_release args
  else
    build_devel args
  end
end

# @param [Hash] args
def build_release(args)
  puts 'Running in RELEASE mode (manual)'

  # check_git_master_branch

  debuild = Debuild.new release: true
  debuild.read_settings

  pull_build_images debuild: debuild, distribution: args[:distribution]

  puts "Building packages for distribution: #{args[:distribution]}"

  build_queue = if args[:skip_package_inspect]
                  args[:packages]
                else
                  make_build_queue(args[:packages], args[:distribution], debuild, force_build: args[:force_package_build])
                end

  build_queue.each do |package|
    puts "Start release build for package #{package}"
    debuild.main(
      package: package,
      distribution: args[:distribution],
      verbose: args[:verbose],
      skip_apt_update: args[:skip_apt_update],
      skip_build: args[:skip_package_build],
      skip_upload: args[:skip_package_upload],
      command: args[:command],
      use_existing_depends_image: args[:use_existing_depends_image]
    )
  end
end

# @param [Debuild] debuild
# @param [String] distribution
def pull_build_images(debuild:, distribution:)
  image_name = debuild.config.image_name
  image_repotag = "#{image_name}:#{distribution}"

  puts "Pulling build image: #{image_repotag}"
  Docker::Image.create 'fromImage' => image_repotag

  puts 'Pulling busybox image'
  pull_busybox_image
end

# @param [Hash] args
def build_devel(args)
  puts 'Running in DEVEL mode'

  debuild = Debuild.new release: false, use_release_images: args[:use_release_images]
  debuild.read_settings

  build_queue = if args[:skip_package_inspect]
                  args[:packages]
                else
                  make_build_queue(args[:packages], args[:distribution], debuild, force_build: args[:force_package_build])
                end

  build_queue.each do |package|
    debuild.main(
      package: package,
      distribution: args[:distribution],
      verbose: args[:verbose],
      skip_apt_update: args[:skip_apt_update],
      skip_build: args[:skip_package_build],
      skip_upload: args[:skip_package_upload],
      command: args[:command],
      use_existing_depends_image: args[:use_existing_depends_image]
    )
  end
end

# @param [Hash] args
def build_gitlab_ci(args)
  puts 'Running in CI mode'

  release = ENV['CI_BUILD_REF_NAME'] == 'master'
  debuild = Debuild.new release: release, use_release_images: args[:use_release_images]
  debuild.read_settings

  packages = get_git_packages
  if packages.empty?
    puts 'No packages to build'
    return
  end

  puts 'Got changed packages to build:'
  pp packages

  pull_build_images debuild: debuild, distribution: args[:distribution]

  puts "Building packages for distribution #{args[:distribution]}"
  make_build_queue(packages, args[:distribution], debuild).each do |package|
    puts "Start release build for package #{package.name}"
    debuild.main(
      package: package,
      distribution: args[:distribution],
      verbose: args[:verbose],
      skip_apt_update: args[:skip_apt_update],
      skip_build: args[:skip_package_build],
      skip_upload: args[:skip_package_upload],
      command: args[:command]
    )
  end

  puts 'End of CI mode'
end

def setup_signal_handler
  Signal.trap('INT') { |signo| destroy_docker_containers signal: signo }
  Signal.trap('TERM') { |signo| destroy_docker_containers signal: signo }
end

if $PROGRAM_NAME == __FILE__
  $stdin.sync = $stdout.sync = $stderr.sync = true

  setup_signal_handler
  main
end
