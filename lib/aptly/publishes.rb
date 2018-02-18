class Aptly
  # Module to work with aptly publish API
  # @see https://www.aptly.info/doc/api/publish/
  module Publishes
    # Default signing settings (skip signing)
    DEFAULT_SIGNING = {
      Skip: true
    }.freeze

    # List published repositories or snapshots
    #
    # @return [String]
    def publish_get
      r = aptly_request 'GET', 'api/publish'
      r.body
    end

    # Publish snapshot or repository
    #
    # @param [String] source_kind
    # @param [Array<String>] sources
    # @param [String] prefix
    # @param [String] distribution
    # @param [String] label
    # @param [String] origin
    # @param [Boolean] force_overwrite
    # @param [Array<String>] architectures
    # @param [Hash] signing
    # @return [String]
    # @raise [Aptly::ExistsError] if publish already exists
    # @raise [Aptly::NotExistsError] if sources don't exist
    def publish_create(source_kind:, sources:, prefix: nil, distribution: nil, label: nil, origin: nil, force_overwrite: false, architectures: ["amd64"], signing: nil)
      data = {}

      data['SourceKind'] = source_kind
      data['Sources'] = sources
      data['ForceOverwrite'] = force_overwrite
      data['Signing'] = signing

      data['Distribution'] = distribution unless distribution.nil?
      data['Label'] = label unless label.nil?
      data['Origin'] = origin unless origin.nil?
      data['Architectures'] = architectures unless architectures.nil?

      puts "DEBUG: request_data=#{data}"

      path = prefix.nil? ? 'api/publish' : "api/publish/#{prefix}"
      r = aptly_request 'POST', path, payload: data

      puts "DEBUG: response=#{r.inspect}"

      case r.code
        when 400
          raise Aptly::ExistsError, "Prefix/distribution #{prefix}/#{distribution} already exists"
        when 404
          raise Aptly::NotExistsError, "Sources #{sources} do not exist"
      end
      r.body
    end

    # Update published repository or switch published snapshot
    #
    # @param [String] prefix
    # @param [String] distribution
    # @param [Array<String>] snapshots
    # @param [Boolean] force_overwrite
    # @param [Hash] signing
    # @return [String]
    def publish_update(prefix:, distribution:, snapshots: nil, force_overwrite: false, signing: DEFAULT_SIGNING)
      data = {
        'ForceOverwrite' => force_overwrite,
        'Signing' => signing
      }
      data['Snapshots'] = snapshots unless snapshots.nil?

      r = aptly_request 'PUT', "api/publish/#{prefix}/#{distribution}", payload: data
      r.body
    end

    # Unpublish repository or snapshot
    #
    # @param [String] prefix
    # @param [Array<String>] distribution
    # @param [Integer] force
    # @return [String]
    def delete(prefix:, distribution:, force: 0)
      r = aptly_request 'DELETE', "api/publish/#{prefix}/#{distribution}?force=#{force}"
      r.body
    end
  end
end
