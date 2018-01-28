require 'erb'
require 'fpm/cookery/recipe'
require 'fpm/cookery/package/dir'
require 'fpm/cookery/source'
require 'fpm/cookery/source_handler'

class FpmPackage < FPM::Cookery::Package::Dir
  def package_setup
    super
    # TODO: fix prefix
    prefix = ''
    fpm.name = "#{prefix}#{recipe.name}"
  end
end

class Recipe < FPM::Cookery::Recipe
  attr_rw :build_depends_cache_key
  attr_rw_list :ubuntu_distribution

  attr_rw :git_repo, :git_tag
  attr_rw :package_name, :package_version, :package_source

  attr_rw_hash :package_source_spec
  attr_rw_hash :apt_depends

  attr_rw_list :configure_params

  def source_handler
    source_obj = if source.nil?
                   FPM::Cookery::Source.new('/dev/null', with: 'noop')
                 else
                   FPM::Cookery::Source.new(source, spec)
                 end
    @source_handler ||= FPM::Cookery::SourceHandler.new(source_obj, cachedir, builddir)
  end

  def initialize; end

  def input(config)
    FpmPackage.new(self, config)
  end
end

class GolangRecipe < Recipe
  attr_rw :gopkg_name

  def prepare_gopath
    @gopath = builddir

    @gobin = @gopath / 'bin'
    @gosrc = @gopath / 'src'

    @gobin.mkdir
    @gosrc.mkdir

    ENV['GOPATH'] = @gopath
    ENV['GOBIN'] = @gobin

    @pkgsrc = @gosrc / gopkg_name
    @pkgsrc.install '.'
  end
end

class TemplateRenderer
  def self.empty_binding
    binding
  end

  def self.render(template_content, locals = {})
    b = empty_binding
    locals.each { |k, v| b.local_variable_set(k, v) }

    # puts b.local_variable_defined?(:template_content) #=> false

    ERB.new(template_content).result(b)
  end
end

# TODO: refactor all recipes to use Recipe class
module FPM
  module Cookery
    class SFRecipe < ::Recipe
    end
  end
end
