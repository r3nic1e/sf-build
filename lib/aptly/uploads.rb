require 'json'

module Uploads
  def get(directory = nil)
    r = if directory.nil?
          aptly_request('GET', 'api/files')
        else
          aptly_request('GET', "api/files/#{directory}")
        end

    raise NotExistsError("Directory #{directory} does not exist") if r.code == 404

    r.body
  end

  def delete_dir(directory, filename = nil)
    r = if filename.nil?
          aptly_request('DELETE', "api/files/#{directory}")
        else
          aptly_request('DELETE', "api/files/#{directory}/#{filename}")
        end

    r.body
  end

  # @return [Array]
  def upload(directory:, files:)
    upload_files = { multipart: true }
    files.each { |f| upload_files[f] = File.open(f, 'rb') }
    r = aptly_request 'POST', "api/files/#{directory}", payload: upload_files
    JSON.parse(r.body)
  end
end
