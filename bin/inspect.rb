#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'optparse'
require 'pp'

require 'debuild'
require 'inspect_package'

# @return [Hash]
def parse_args
  options = {
    distribution: 'focal',
    verbose: false
  }
  # @type [Debuild::Settings]
  settings = Debuild::Settings.instance

  OptionParser.new do |parser|
    parser.on '-d', '--distribution', %w[bionic focal], 'Ubuntu distribution to build for', :REQUIRED do |v|
      options[:distribution] = v
      settings.distribution = v
    end
    parser.on '-v', '--[no-]verbose', 'Show build logs' do |v|
      options[:verbose] = v
      settings.verbose = true
    end
    parser.on '-h', '--help' do
      puts parser
      exit
    end
  end.parse! ARGV
  ARGV.dup
end

def main
  packages = parse_args
  packages = debuild.config.packages if packages.empty?

  debuild = Debuild.new
  debuild.read_settings

  puts "DEBUG: got #{packages.length} packages to inspect:"
  pp packages

  build_queue = make_build_queue packages, debuild

  puts "Found #{build_queue.length} packages to build:"
  pp build_queue.collect(&:name)
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
