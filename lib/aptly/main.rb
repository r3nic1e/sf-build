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
    #RestClient.log = 'stderr'
  end

  include Publishes
  include Repos
  include Snapshots
  include Uploads

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
      headers = { 'Content-Type' => 'application/json' }
    end

    begin
      RestClient::Request.execute(method: method.downcase.to_sym, url: url, payload: payload, headers: headers)
    rescue RestClient::ExceptionWithResponse => err
      err.response
    end
  end
end
