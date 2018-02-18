require_relative 'errors'

class Aptly
  # Module to work with aptly repository API
  # @see https://www.aptly.info/doc/api/repos/
  module Repos
    # Create empty repository
    #
    # @param [String] name
    # @param [String] comment
    # @param [String] default_distribution
    # @param [String] default_component
    # @return [String]
    # @raise [Aptly:ExistsError] if repo already exists
    def repo_create(name:, comment: nil, default_distribution: nil, default_component: nil)
      data = {}
      data['Name'] = name
      data['Comment'] = comment unless comment.nil?
      data['DefaultDistribution'] = default_distribution unless default_distribution.nil?
      data['DefaultComponent'] = default_component unless default_component.nil?

      r = aptly_request 'POST', 'api/repos', payload: data

      if r.code == 400
        raise Aptly::ExistsError, "Repo #{name} already exists"
      end
      r.body
    end

    # Get information about repository
    #
    # @param [String] name
    # @return [String]
    # @raise [Aptly::NotExistsError] if repo doesn't exist
    def repo_show(name:)
      r = aptly_request 'GET', "api/repos/#{name}"
      raise Aptly::NotExistsError, "Repo #{name} does not exist" if r.code == 404
      r.body
    end

    # Update repository information
    #
    # @param [String] name
    # @param [String] comment
    # @param [String] default_distribution
    # @param [String] default_component
    # @return [String]
    # @raise [Aptly::NotExistsError] if repo doesn't exist
    def repo_update(name:, comment: nil, default_distribution: nil, default_component: nil)
      data = {}
      data['Comment'] = comment unless comment.nil?
      data['DefaultDistribution'] = default_distribution unless default_distribution.nil?
      data['DefaultComponent'] = default_component unless default_component.nil?

      r = aptly_request 'PUT', "api/repos/#{name}", payload: data
      raise Aptly::NotExistsError, "Repo #{name} does not exist" if r.code == 404
      r.body
    end

    # List available repositories
    #
    # @return [String]
    def repo_get
      r = aptly_request 'GET', 'api/repos'
      r.body
    end

    # Delete repository
    #
    # @param [String] name
    # @param [Integer] force
    # @return [String]
    # @raise [Aptly::NotExistsError] if repo doesn't exist
    # @raise [Exception] if cannot remove repo
    def repo_delete(name:, force: 0)
      r = aptly_request 'DELETE', "api/repos/#{name}?force=#{force}"
      case r.code
        when 404
          raise Aptly::NotExistsError, "Repo #{name} does not exist"
        when 409
          raise Exception, "Cannot remove repo #{name}: #{r.body}"
      end
      r.body
    end

    # Import packages to repository from remote directory
    #
    # @param [String] name
    # @param [String] dir
    # @param [Integer] no_remove
    # @param [Integer] force_replace
    # @return [String]
    # @raise [Aptly::NotExistsError] if repo doesn't exist
    def repo_add_packages_from_dir(name:, dir:, no_remove: 0, force_replace: 0)
      r = aptly_request 'POST', "api/repos/#{name}/file/#{dir}?noRemove=#{no_remove}&forceReplace=#{force_replace}"

      raise Aptly::NotExistsError, "Repo #{name} does not exist" if r.code == 404
      r.body
    end

    # Import remote packages to repository
    #
    # @param [String] name
    # @param [Array<String>] packages
    # @return [String]
    # @raise [Aptly::NotExistsError] if repo doesn't exist
    # @raise [Exception] if conflict detected
    def repo_add_packages_by_name(name:, packages:)
      data = {'PackageRefs' => packages}

      r = aptly_request('POST', "api/repos/#{name}/packages", payload: data)

      case r.code
        when 400
          raise Exception, 'Conflict detected while adding packages'
        when 404
          raise Aptly::NotExistsError, "Repo #{name} or packages #{packages} do not exist"
      end
      r.body
    end

    # Remove packages from repository
    #
    # @param [String] name
    # @param [Array<String>] packages
    # @return [String]
    # @raise [Aptly::NotExistsError] if repo doesn't exist
    def repo_delete_packages_by_name(name:, packages:)
      data = {'PackageRefs' => packages}

      r = aptly_request('DELETE', "api/repos/#{name}/packages", payload: data)

      raise Aptly::NotExistsError, "Repo #{name} does not exist" if r.code == 404
      r.body
    end

    # Search for packages in repository
    #
    # @param [String] repo
    # @param [String] name
    # @param [String] version
    # @param [String] comp_symbol
    # @return [String]
    # @raise [Aptly::NotExistsError] if repo doesn't exist
    def repo_search_package(repo:, name: nil, version: nil, comp_symbol: '=')
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
end
