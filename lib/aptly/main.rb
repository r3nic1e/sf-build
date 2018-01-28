require 'unirest'
require 'uri'

require_relative 'publishes'
require_relative 'repos'
require_relative 'snapshots'
require_relative 'uploads'

class Aptly
  # @param [String] aptly_api_url
  def initialize(aptly_api_url)
    @aptly_api_url = aptly_api_url
  end

  # @param [Symbol] prefix
  # @param [Array] methods
  def self.rename_methods(prefix, *methods)
    methods.each do |old_name|
      new_name = "#{prefix.to_s}_#{old_name.to_s}".to_sym
      alias_method new_name, old_name
    end
  end

  # @param [Module] include_module
  # @param [Symbol] prefix
  def self.include_rename(include_module, prefix)
    methods = include_module.instance_methods(false).map { |m| m.to_sym }
    include include_module
    rename_methods prefix, *methods
  end


  include_rename Publishes, :publish
  include_rename Repos, :repo
  include_rename Snapshots, :snapshot
  include_rename Uploads, :upload

  private
  # @param [String] method
  # @param [String] path
  # @param [Hash] kwargs
  # @return [Unirest::HttpResponse]
  def aptly_request(method, path, **kwargs)
    url = URI.join(@aptly_api_url, path).to_s

    # dirty hack to send json
    unless kwargs[:headers]
      kwargs[:parameters] = kwargs[:parameters].to_json
      kwargs[:headers] = {'Content-Type': 'application/json'}
    end

    Unirest.method(method.downcase).call(url, **kwargs)
  end
end