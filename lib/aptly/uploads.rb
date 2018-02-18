require 'json'

class Aptly
  # Module to work with aptly file upload API
  # @see https://www.aptly.info/doc/api/files/
  module Uploads
    # List remote directories or files in remote directory
    #
    # @param [String] directory
    # @return [String]
    # @raise [Aptly::NotExistsError] if directory doesn't exist
    def upload_get(directory = nil)
      r = if directory.nil?
            aptly_request('GET', 'api/files')
          else
            aptly_request('GET', "api/files/#{directory}")
          end

      raise NotExistsError("Directory #{directory} does not exist") if r.code == 404

      r.body
    end

    # Delete remote directory
    #
    # @param [String] directory
    # @param [String] filename
    # @return [String]
    def upload_delete_dir(directory, filename = nil)
    r = if filename.nil?
          aptly_request('DELETE', "api/files/#{directory}")
        else
          aptly_request('DELETE', "api/files/#{directory}/#{filename}")
        end

    r.body
    end

    # Upload files to remote directory
    #
    # @param [String] directory
    # @param [Array<String>] files
    # @return [Array]
    def upload_upload(directory:, files:)
      upload_files = {multipart: true}
      files.each {|f| upload_files[f] = File.open(f, 'rb')}
      r = aptly_request 'POST', "api/files/#{directory}", payload: upload_files
      JSON.parse(r.body)
    end
  end
end
