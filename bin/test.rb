#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'optparse'
require 'debuild'

# @return [Hash]
def get_args
  options = {
    distribution: 'precise',
    verbose: false
  }
  OptionParser.new do |parser|
    parser.on '-d', '--distribution', %w[precise trusty xenial], 'Ubuntu distribution to build for', :REQUIRED do |v|
      options[:distribution] = v
    end
    parser.on '-v', '--[no-]verbose', 'Show build logs' do |v|
      options[:verbose] = v
    end
    parser.on '--[no-]skip-available-packages', 'Skip available packages check' do |v|
      options[:skip_available_packages] = v
    end
    parser.on '--[no-]use-release-images', 'Use release images for test' do |v|
      options[:use_release_images] = v
    end
    parser.on '-c', '--command=NAME', 'Additional command to run in test container' do |v|
      options[:command] = v
    end
    parser.on '-h', '--help' do
      puts parser
      exit
    end
  end.parse! ARGV
  options[:package] = ARGV[0]
  options
end

def setup_signal_handler
  Signal.trap('INT') { |signo| destroy_docker_containers signal: signo }
  Signal.trap('TERM') { |signo| destroy_docker_containers signal: signo }
end

def main
  args = get_args

  debuild = Debuild.new release: false, use_release_images: args[:use_release_images]
  debuild.read_settings

  debuild.test(
    package_name: args[:package],
    distribution: args[:distribution],
    verbose: args[:verbose],
    command: args[:command],
    skip_available_packages: args[:skip_available_packages]
  )
end

if $PROGRAM_NAME == __FILE__
  $stdin.sync = $stdout.sync = $stderr.sync = true

  setup_signal_handler
  main
end
