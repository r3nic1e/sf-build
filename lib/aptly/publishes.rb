module Publishes
  DEFAULT_SIGNING = {
      Skip: true,
  }

  def get
    r = aptly_request 'GET', 'api/publish'
    r.body
  end

  def create(source_kind:, sources:, prefix: nil, distribution: nil, label: nil, origin: nil, force_overwrite: false, architectures: ["amd64"], signing: nil)
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
    if prefix.nil?
      r = aptly_request 'POST', 'api/publish', parameters: data
    else
      r = aptly_request 'POST', "api/publish/#{prefix}", parameters: data
    end

    puts "DEBUG: response=#{r.inspect}"

    case r.code
      when 400
        raise Aptly::ExistsError, "Prefix/distribution #{prefix}/#{distribution} already exists"
      when 404
        raise Aptly::NotExistsError, "Sources #{sources} do not exist"
    end
    r.body
  end

  def update(prefix:, distribution:, snapshots: nil, force_overwrite: false, signing: DEFAULT_SIGNING)
    data = {
        'ForceOverwrite': force_overwrite,
        'Signing': signing,
    }
    data['Snapshots'] = snapshots unless snapshots.nil?

    r = aptly_request 'PUT', "api/publish/#{prefix}/#{distribution}", parameters: data
    r.body
  end

  def delete(prefix:, distribution:, force: 0)
    r = aptly_request 'DELETE', "api/publish/#{prefix}/#{distribution}?force=#{force}"
    r.body
  end
end
