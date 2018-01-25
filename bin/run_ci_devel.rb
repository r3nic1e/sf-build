#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require_relative 'generate_images'

def main
  ref_name = ENV['CI_BUILD_REF_NAME']
  unless ref_name
    puts 'Not in CI environment. Aborting'
    exit 1
  end

  re_check_ref = /^dev-[a-z]+-[a-z]+(?:-[a-z0-9].*)?$/

  unless ref_name =~ re_check_ref
    puts 'Invalid ref name. Aborting'
    exit 1
  end

  ref_tokens = ref_name.split '-'

  username = ref_tokens[1]
  distribution = ref_tokens[2]

  create_devel_config username: username, use_release_images: true

  exec('ruby', 'bin/build.rb', "--distribution=#{distribution}", '--use-release-images', '--verbose')
end

if $PROGRAM_NAME == __FILE__
  $stdin.sync = $stdout.sync = $stderr.sync = true

  main
end
