#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'optparse'
require 'pp'

require 'debuild'
require 'inspect_package'

# @return [Hash]
def parse_args
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
    parser.on '-h', '--help' do
      puts parser
      exit
    end
  end.parse! ARGV
  options[:packages] = ARGV.dup
  options
end

def main
  args = parse_args

  debuild = Debuild.new
  debuild.read_settings

  packages = if args[:packages].empty?
               debuild.config.packages
             else
               args[:packages]
             end

  puts "DEBUG: got #{packages.length} packages to inspect:"
  pp packages

  build_queue = make_build_queue packages, args[:distribution], debuild

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
