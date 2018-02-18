class Aptly
  # Module to work with aptly snapshot API
  # @see https://www.aptly.info/doc/api/snapshots/
  module Snapshots
    # List available snapshots
    #
    # @return [String]
    def snapshot_get
      r = aptly_request('GET', 'api/snapshots')
      r.body
    end

    # Create snapshot from repo
    #
    # @param [String] repo
    # @param [String] name
    # @param [String] description
    # @return [String]
    # @raise [Aptly::NotExistsError] if repo doesn't exist
    # @raise [Aptly::NoPackagesError] if repo doesn't contain any packages
    # @raise [Aptly::ExistsError] if snapshot already exist
    def snapshot_create_from_repo(repo:, name:, description: nil)
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
            raise Aptly::ExistsError("Snapshot #{name} already exists")
          end
        when 404
          raise Aptly::NotExistsError("Repo #{repo} does not exist")
      end
      r.body
    end

    # Create snapshot from package list
    #
    # @param [String] name
    # @param [String] description
    # @param [Array<String>] source_snapshots
    # @param [Array<String>] package_refs
    # @return [String]
    # @raise [Aptly::ExistsError] if snapshot already exist
    # @raise [Aptly::NotExistsError] if source snapshots or packages don't exist
    def snapshot_create_from_packages(name:, description: nil, source_snapshots: nil, package_refs: nil)
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

    # Update snapshot description or name
    #
    # @param [String] name
    # @param [String] new_name
    # @param [String] new_description
    # @return [String]
    # @raise [Aptly::NotExistsError] if snapshot doesn't exist
    # @raise [Aptly::ExistsError] if snapshot with new name already exist
    def snapshot_update(name:, new_name: nil, new_description: nil)
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

    # Get information about repository
    #
    # @param [String] name
    # @return [String]
    # @raise [Aptly::NotExistsError] if snapshot doesn't exist
    def snapshot_show(name:)
      r = aptly_request('GET', "api/snapshots/#{name}")
      if r.code == 404
        raise Aptly::NotExistsError("Snapshot #{name} does not exist")
      end
      r.body
    end

    # Delete snapshot
    #
    # @param [String] name
    # @param [Integer] force
    # @return [String]
    # @raise [Aptly::NotExistsError] if snapshot doesn't exist
    # @raise [Exception] if cannot remove snapshot
    def snapshot_delete(name:, force: 0)
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

    # Show difference between two snapshots
    # @param [String] left
    # @param [String] right
    # @return [String]
    def snapshot_diff(left:, right:)
      r = aptly_request('GET', "api/snapshots/#{left}/diff/#{right}")
      r.body
    end

    # List packages in snapshot
    #
    # @param [String] name
    # @return [String]
    # @raise [Aptly::NotExistsError] if snapshot doesn't exist
    def snapshot_get_package_list(name:)
      r = aptly_request('GET', "api/snapshots/#{name}/packages")
      if r.code == 404
        raise Aptly::NotExistsError("Snapshot #{name} does not exist")
      end
      r.body
    end

    # Search for packages in snapshot
    #
    # @param [String] snapshot
    # @param [String] name
    # @param [String] version
    # @param [String] comp_symbol
    # @return [String]
    # @raise [Aptly::NotExistsError] if snapshot doesn't exist
    def snapshot_search_package(snapshot:, name:, version: nil, comp_symbol: '=')
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
end