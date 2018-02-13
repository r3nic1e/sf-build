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

    def main(package:, distribution:, verbose: false, skip_apt_update: false, **_)
      package_name = if package.is_a? SFPackage
                       package.name
                     else
                       package
                     end

      update_timestamp

      clean_deb distribution: distribution

      available_packages = packages

      unless available_packages.include? package_name
        puts "Unknown package #{package_name}, use one of these: #{available_packages}"
        return
      end

      build_deb package: package, distribution: distribution, verbose: verbose, skip_apt_update: skip_apt_update

      update_aptly distribution: distribution
    end

  end
end
