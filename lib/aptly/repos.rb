require_relative 'errors'

module Repos
  def create(name:, comment: nil, default_distribution: nil, default_component: nil)
    data = {'Name': name}
    data['Comment'] = comment unless comment.nil?
    data['DefaultDistribution'] = default_distribution unless default_distribution.nil?
    data['DefaultComponent'] = default_component unless default_component.nil?

    r = aptly_request 'POST', 'api/repos', payload: data

    if r.code == 400
      raise Aptly::ExistsError.new("Repo #{name} already exists")
    end
    r.body
  end

  def show(name:)
    r = aptly_request 'GET', "api/repos/#{name}"
    if r.code == 404
      raise Aptly::NotExistsError.new("Repo #{name} does not exist")
    end
    r.body
  end

  def update(name:, comment: nil, default_distribution: nil, default_component: nil)
    data = {}
    data['Comment'] = comment unless comment.nil?
    data['DefaultDistribution'] = default_distribution unless default_distribution.nil?
    data['DefaultComponent'] = default_component unless default_component.nil?

    r = aptly_request 'PUT', "api/repos/#{name}", payload: data
    if r.code == 404
      raise Aptly::NotExistsError.new("Repo #{name} does not exist")
    end
    r.body
  end

  def get
    r = aptly_request 'GET', 'api/repos'
    r.body
  end

  def delete(name:, force: 0)
    r = aptly_request 'DELETE', "api/repos/#{name}?force=#{force}"
    case r.code
      when 404
        raise Aptly::NotExistsError.new("Repo #{name} does not exist")
      when 409
        raise Exception.new("Cannot remove repo #{name}: #{r.body}")
    end
    r.body
  end

  def add_packages_from_dir(name:, dir:, no_remove: 0, force_replace: 0)
    r = aptly_request 'POST', "api/repos/#{name}/file/#{dir}?noRemove=#{no_remove}&forceReplace=#{force_replace}"

    if r.code == 404
      raise Aptly::NotExistsError.new("Repo #{name} does not exist")
    end
    r.body
  end


  def add_packages_by_name(name:, packages:)
    data = {'PackageRefs': packages}

    r = aptly_request('POST', "api/repos/#{name}/packages", payload: data)

    case r.code
      when 400
        raise Exception.new('Conflict detected while adding packages')
      when 404
        raise Aptly::NotExistsError.new("Repo #{name} or packages #{packages} do not exist")
    end
    r.body
  end


  def delete_packages_by_name(name:, packages:)
    data = {'PackageRefs': packages}

    r = aptly_request('DELETE', "api/repos/#{name}/packages", payload: data)

    if r.code == 404
      raise Aptly::NotExistsError.new("Repo #{name} does not exist")
    end
    r.body
  end


  def search_package(repo:, name: nil, version: nil, comp_symbol: '=')
    data = {}
    unless name.nil?
      if version.nil?
        data['q'] = name
      else
        data['q'] = '{} ({} {})'.format(name, comp_symbol, version)
      end
    end

    r = aptly_request('GET', "api/repos/#{repo}/packages", payload: data)

    if r.code == 404
      raise NotExistsError("repo #{repo} does not exist")
    end
    r.body
  end
end
