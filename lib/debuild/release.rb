require 'yaml'
require_relative 'config'
require_relative 'repository'

class Debuild
  class ReleaseConfig < Config
    def initialize(*)
      settings = YAML.load_file 'release.yml'
      update_timestamp

      @settings = settings

      @aptly = Aptly.new aptly_api_url
    end
  end
end
