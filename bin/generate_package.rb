#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'erb'

RECIPE_TEMPLATE = <<RECIPE.freeze
require_relative '../recipe'

class <%= class_name %> < SFRecipe
  description '<%= package_name %> description'

  name '<%= package_name %>'
  version '0.0.0'
  revision 1

  #replaces '<%= package_name %>'
  #conflicts '<%= package_name %>'

  git_repo 'https://github.com/foo/bar.git'

  source git_repo,
    with: 'git',
    tag: "v\#{version}"

  build_depends []
  depends []

  configure_params []

  def build
    configure *configure_params
    make %Q(--jobs=\#{`nproc`.to_i + 1})
  end

  def install
    make :install, DESTDIR: destdir
  end
end
RECIPE

def main
  packages = ARGV.dup
  packages.each do |package|
    package_dir = File.join 'recipes', package

    if Dir.exist? package_dir
      puts "Packages #{package} already exists"
      next
    end

    recipe_file = File.join package_dir, 'recipe.rb'

    Dir.mkdir package_dir, 0o755

    class_name = package.tr('_', '-').split('-').map(&:capitalize).join('')

    renderer = ERB.new RECIPE_TEMPLATE
    b = binding
    b.local_variable_set :class_name, class_name
    b.local_variable_set :package_name, package
    result_template = renderer.result b

    File.open recipe_file, 'w+' do |f|
      f.write result_template
    end
  end
end

main if $PROGRAM_NAME == __FILE__
