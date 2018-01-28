module Snapshots
  def get
    r = aptly_request('GET', 'api/snapshots')
    r.body
  end


  def create_from_repo(repo:, name:, description: nil)
    data = {Name: name}
    data['Description'] = description unless description.nil?

    r = aptly_request 'POST', "api/repos/#{repo}/snapshots", payload: data
    puts "DEBUG: #{r.body}"

    case r.code
      when 400
        result = r.body
        if result[0]['error'] == "local repo doesn't have packages"
          raise Aptly::NoPackagesError("Repo #{repo} does not have any packages")
        else
          raise Aptly::ExistsError.new("Snapshot #{name} already exists")
        end
      when 404
        raise Aptly::NotExistsError("Repo #{repo} does not exist")
    end
    r.body
  end

  def create_from_packages(name:, description: nil, source_snapshots: nil, package_refs: nil)
    data = {'Name' => name}
    data['Description'] = description unless description.nil?
    data['SourceSnapshots'] = source_snapshots unless source_snapshots.nil?
    data['PackageRefs'] = package_refs unless package_refs.nil?

    r = aptly_request('POST', 'api/snapshots', payload: data)

    case r.code
      when 400
        raise Aptly::ExistsError("Snapshot #{name} already exists")
      when 404
        raise Aptly::NotExistsError("Source snapshots #{source_snapshots} or packages #{package_refs} do not exist")
    end
    return r.body
  end


  def update(name:, new_name: nil, new_description: nil)
    if not new_name.nil?
      data = {'Name': new_name}
    elsif not new_description.nil?
      data = {'Description': new_description}
    else
      return nil
    end

    r = aptly_request('PUT', "api/snapshots/#{name}", payload: data)

    case r.code
      when 404
        raise Aptly::NotExistsError("Snapshot #{name} does not exist")
      when 409
        raise Aptly::ExistsError("Name #{new_name} already used")
      else
        return r.body
    end
  end


  def show(name:)
    r = aptly_request('GET', "api/snapshots/#{name}")
    if r.code == 404
      raise Aptly::NotExistsError("Snapshot #{name} does not exist")
    end
    r.body
  end


  def delete(name:, force: 0)
    r = aptly_request('DELETE', "api/snapshots/#{name}?force=#{force}")
    print("DEBUG: #{}".format(r.text))

    case r.code
      when 404
        raise Aptly::NotExistsError("Snapshot #{name} does not exist")
      when 409
        raise Exception("Cannot remove snapshot #{name}: #{r.body}")
    end
    r.body
  end


  def diff(left:, right:)
    r = aptly_request('GET', "api/snapshots/#{left}/diff/#{right}")
    r.body
  end


  def get_package_list(name:)
    r = aptly_request('GET', "api/snapshots/#{name}/packages")
    if r.code == 404
      raise Aptly::NotExistsError("Snapshot #{name} does not exist")
    end
    r.body
  end


  def search_package(snapshot:, name:, version: nil, comp_symbol: '=')
    if version.nil?
      data = {'q': name}
    else
      data = {'q': "#{name} (#{comp_symbol} #{version})"}
    end

    r = aptly_request('GET', "api/snapshots/#{snapshot}/packages", payload: data)
    if r.code == 404
      raise Aptly::NotExistsError("Snapshot #{snapshot} does not exist")
    end
    r.body
  end
end
