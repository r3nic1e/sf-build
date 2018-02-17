#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'optparse'
require_relative 'generate_images'

# @return [Hash]
def get_args
  options = {
    use_release_images: false
  }
  OptionParser.new do |parser|
    parser.on '-uNAME', '--username=NAME' do |v|
      options[:username] = v
    end
    parser.on '--use-release-images' do |v|
      options[:use_release_images] = v
    end
  end.parse! ARGV
  options
end

if $PROGRAM_NAME == __FILE__
  args = get_args
  create_devel_config args
end
