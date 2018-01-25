module Uploads
  def get(directory=nil)
    if directory.nil?
      r = aptly_request('GET', 'api/files')
    else
      r = aptly_request('GET', "api/files/#{directory}")
    end

    if r.code == 404
      raise NotExistsError("Directory #{directory} does not exist")
    end

    r.body
  end


  def delete_dir(directory, filename=nil)
    if filename.nil?
      r = aptly_request('DELETE', "api/files/#{directory}")
    else
      r = aptly_request('DELETE', "api/files/#{directory}/#{filename}")
    end

    r.body
  end


  # @return [Array]
  def upload(directory:, files:)
    upload_files = {}
    files.each { |f| upload_files[f] = File.open(f, 'rb') }
    r = aptly_request 'POST', "api/files/#{directory}", parameters: upload_files, headers: {'Content-Type': 'multipart/form-data'}
    r.body
  end
end
