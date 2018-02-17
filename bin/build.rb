#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'optparse'
require 'git'

require 'debuild'
require 'inspect_package'
require 'git_helper'

# @return [Hash]
def parse_args
  settings = Debuild::Settings.instance

  OptionParser.new do |parser|
    parser.on '-d', '--distribution', %w[natty precise trusty xenial], 'Ubuntu distribution to build for', :REQUIRED do |v|
      settings.distribution = v
    end
    parser.on '-v', '--verbose', 'Show build logs' do |v|
      settings.verbose = true
    end
    parser.on '--skip-apt-update', "Skip 'apt-get update' before build" do |v|
      settings.skip_apt_update = true
    end
    parser.on '--skip-package-build', 'Skip build, only upload package' do |v|
      settings.skip_package_build = true
    end
    parser.on '--skip-package-upload', 'Skip upload, only build package' do |v|
      settings.skip_package_upload = true
    end
    parser.on '--force-package-build', 'Force package build if already uploaded' do |v|
      settings.force_package_build = true
    end
    parser.on '--skip-package-inspect', 'Skip package inspection, ignore build dependencies' do |v|
      settings.skip_package_inspect = true
    end
    parser.on '--use-existing-depends-image', 'Use existing build depends image' do |v|
      settings.use_existing_depends_image = true
    end
    parser.on '--release', 'Build and push packages to production' do |v|
      settings.release = true
    end
    parser.on '--use-release-images', 'Use release images for devel build' do |v|
      settings.use_release_images = true
    end
    parser.on '--command=COMMAND', 'Override command running in container' do |v|
      settings.command = v
    end
    parser.on '-h', '--help' do
      puts parser
      exit
    end
  end.parse! ARGV
  ARGV.dup
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
  packages = parse_args
  if detect_ci
    build_ci
  elsif Debuild::Settings.instance.release
    build_release packages
  else
    build_devel packages
  end
end

# @param [Array] packages
def build_release(packages)
  puts 'Running in RELEASE mode (manual)'

  # @todo uncomment
  # check_git_master_branch

  debuild = Debuild.new
  debuild.read_settings
  debuild.pull_build_images

  puts "Building packages for distribution: #{debuild.settings.distribution}"

  make_build_queue(packages, debuild).each do |package|
    puts "Start release build for package #{package}"
    debuild.main package: package
  end
end

# @param [Array] packages
def build_devel(packages)
  puts 'Running in DEVEL mode'

  debuild = Debuild.new
  debuild.read_settings

  make_build_queue(packages, debuild).each do |package|
    debuild.main package: package
  end
end

def detect_ci
  ENV.key? 'CI_BUILD_REF_NAME'
end

def build_ci
  puts 'Running in CI mode'

  Debuild::Settings.instance.release = ENV['CI_BUILD_REF_NAME'] == 'master'
  debuild = Debuild.new
  debuild.read_settings

  packages = get_git_packages
  if packages.empty?
    puts 'No packages to build'
    return
  end

  puts 'Got changed packages to build:'
  pp packages

  debuild.pull_build_images

  puts "Building packages for distribution #{debuild.settings.distribution}"
  make_build_queue(packages, debuild).each do |package|
    puts "Start release build for package #{package.name}"
    debuild.main package: package
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
