require_relative 'errors'

module Repos
  def create(name:, comment: nil, default_distribution: nil, default_component: nil)
    data = {}
    data['Name'] = name
    data['Comment'] = comment unless comment.nil?
    data['DefaultDistribution'] = default_distribution unless default_distribution.nil?
    data['DefaultComponent'] = default_component unless default_component.nil?

    r = aptly_request 'POST', 'api/repos', payload: data

    if r.code == 400
      p r.body
      raise Aptly::ExistsError, "Repo #{name} already exists"
    end
    r.body
  end

  def show(name:)
    r = aptly_request 'GET', "api/repos/#{name}"
    raise Aptly::NotExistsError, "Repo #{name} does not exist" if r.code == 404
    r.body
  end

  def update(name:, comment: nil, default_distribution: nil, default_component: nil)
    data = {}
    data['Comment'] = comment unless comment.nil?
    data['DefaultDistribution'] = default_distribution unless default_distribution.nil?
    data['DefaultComponent'] = default_component unless default_component.nil?

    r = aptly_request 'PUT', "api/repos/#{name}", payload: data
    raise Aptly::NotExistsError, "Repo #{name} does not exist" if r.code == 404
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
      raise Aptly::NotExistsError, "Repo #{name} does not exist"
    when 409
      raise Exception, "Cannot remove repo #{name}: #{r.body}"
    end
    r.body
  end

  def add_packages_from_dir(name:, dir:, no_remove: 0, force_replace: 0)
    r = aptly_request 'POST', "api/repos/#{name}/file/#{dir}?noRemove=#{no_remove}&forceReplace=#{force_replace}"

    raise Aptly::NotExistsError, "Repo #{name} does not exist" if r.code == 404
    r.body
  end

  def add_packages_by_name(name:, packages:)
    data = { 'PackageRefs' => packages }

    r = aptly_request('POST', "api/repos/#{name}/packages", payload: data)

    case r.code
    when 400
      raise Exception, 'Conflict detected while adding packages'
    when 404
      raise Aptly::NotExistsError, "Repo #{name} or packages #{packages} do not exist"
    end
    r.body
  end

  def delete_packages_by_name(name:, packages:)
    data = { 'PackageRefs' => packages }

    r = aptly_request('DELETE', "api/repos/#{name}/packages", payload: data)

    raise Aptly::NotExistsError, "Repo #{name} does not exist" if r.code == 404
    r.body
  end

  def search_package(repo:, name: nil, version: nil, comp_symbol: '=')
    data = {}
    unless name.nil?
      data['q'] = if version.nil?
                    name
                  else
                    '{} ({} {})'.format(name, comp_symbol, version)
                  end
    end

    r = aptly_request 'GET', "api/repos/#{repo}/packages", payload: data

    raise Aptly::NotExistsError, "repo #{repo} does not exist" if r.code == 404
    r.body
  end
end
