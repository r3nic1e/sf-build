require 'rest-client'
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
      new_name = "#{prefix}_#{old_name}".to_sym
      alias_method new_name, old_name
    end
  end

  # @param [Module] include_module
  # @param [Symbol] prefix
  def self.include_rename(include_module, prefix)
    methods = include_module.instance_methods(false).map(&:to_sym)
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
  # @param [Object] payload
  # @param [Hash] headers
  # @return [RestClient::Response]
  def aptly_request(method, path, payload: nil, headers: {})
    url = URI.join(@aptly_api_url, path).to_s

    # dirty hack to send json
    if headers.empty? and not (not payload.nil? and payload.key? :multipart)
      payload = payload.to_json
      headers = { Content_Type: :json }
    end

    begin
      RestClient.method(method.downcase).call(url, payload, headers)
    rescue RestClient::ExceptionWithResponse => err
      err.response
    end
  end
end
