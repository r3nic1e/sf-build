require 'yaml'
require_relative 'config'
require_relative 'repository'

class Debuild
  def read_settings(release: false)
    settings = YAML.load_file 'release.yml'
    create_config settings: settings, release_settings: settings.dup

    @aptly = Aptly.new @config.aptly_api_url
  end

  def main(package:, distribution:, verbose: false, skip_apt_update: false, **_)
    package_name = if package.is_a? SFPackage
                     package.name
                   else
                     package
                   end

    read_settings if @config.nil?

    @config.update_timestamp

    clean_deb distribution: distribution

    available_packages = @config.packages

    unless available_packages.include? package_name
      puts "Unknown package #{package_name}, use one of these: #{available_packages}"
      return
    end

    build_deb package: package, distribution: distribution, verbose: verbose, skip_apt_update: skip_apt_update

    update_aptly distribution: distribution
  end

  def update_aptly(distribution:, skip_upload: false)
    deb_path = File.join @config.output, distribution
    deb_abs_path = File.absolute_path deb_path

    release_repo = "#{@config.aptly_repo}-#{distribution}"

    begin
      result = @aptly.repo_create name: release_repo, default_distribution: distribution
      puts "Repo #{release_repo} created"
      puts result
    rescue Aptly::ExistsError
      puts "Repo #{release_repo} already exists"
    end

    upload_deb directory: deb_abs_path, repo: release_repo unless skip_upload
    update_repo repo: release_repo, distribution: distribution

    puts 'Done'
  end
end
