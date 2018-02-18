require 'rest-client'
require 'uri'

require_relative 'publishes'
require_relative 'repos'
require_relative 'snapshots'
require_relative 'uploads'

# High level aptly api client
# @see https://www.aptly.info/doc/api/
class Aptly
  # @param [String] aptly_api_url base aptly URL
  def initialize(aptly_api_url)
    @aptly_api_url = aptly_api_url
    # RestClient.log = 'stderr'
  end

  include Publishes
  include Repos
  include Snapshots
  include Uploads

  private

  # Creates request to aptly api and returns response
  #
  # @param [String] method HTTP method to use
  # @param [String] path URL path after base aptly URL
  # @param [Object] payload GET arguments or request body
  # @param [Hash] headers HTTP request headers
  # @return [RestClient::Response] aptly response
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
