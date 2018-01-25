require 'yaml'
require_relative 'config'
require_relative 'repository'

class Hash
  def deep_dup
    each_with_object(dup) do |(key, value), hash|
      hash[key] = (value.is_a?(Hash) ? value.deep_dup : value)
    end
  end

  # http://apidock.com/rails/v4.2.7/Hash/deep_merge%21
  def deep_merge(other_hash, &block)
    other_hash.each_pair do |current_key, other_value|
      this_value = self[current_key]

      self[current_key] = if this_value.is_a?(Hash) && other_value.is_a?(Hash)
                            this_value.deep_merge(other_value, &block)
                          else
                            if block_given? && key?(current_key)
                              yield(current_key, this_value, other_value)
                            else
                              other_value
                            end
                          end
    end

    self
  end
end

class Debuild
  def read_settings(image_suffix: '-devel', skip_devel: false)
    release_settings = YAML.load_file 'release.yml'
    settings = release_settings.deep_dup

    begin
      devel_settings = YAML.load_file 'devel.yml'

      unless devel_settings.key?('aptly') && devel_settings['aptly'].key?('repo')
        puts "No 'aptly.repo' section in devel.yml"
        exit 1
      end

      if devel_settings['aptly']['repo'] == release_settings['aptly']['repo']
        puts "Bad 'aptly.repo' section in devel.yml"
        exit 1
      end

      settings = settings.deep_merge devel_settings
    rescue StandardError => e
      unless skip_devel
        pp e
        puts 'Failed to read devel.yml, beware possible production corruption'
        exit 1
      end
    end

    settings['image']['name'] += image_suffix if image_suffix

    create_config settings: settings, release_settings: release_settings, use_release_images: @use_release_images

    @aptly = Aptly.new @config.aptly_api_url
  end

  def main(package:, distribution:, verbose: false, skip_apt_update: false, skip_build: false, skip_upload: false,
           command: nil, use_existing_depends_image: false)
    package_name = if package.is_a? SFPackage
                     package.name
                   else
                     package
                   end

    read_settings if @config.nil?

    @config.update_timestamp

    available_packages = @config.packages

    unless available_packages.include? package_name
      puts "Unknown package #{package_name}, use one of these: #{available_packages}"
      exit 1
    end

    unless skip_build
      clean_deb distribution: distribution
      build_deb package: package, distribution: distribution, verbose: verbose, skip_apt_update: skip_apt_update,
                command: command, use_existing_depends_image: use_existing_depends_image
    end

    update_aptly distribution: distribution unless skip_upload
  end

  def test(package_name:, distribution:, verbose: false, skip_available_packages: false, command: nil)
    read_settings image_suffix: '-test'

    available_packages = @config.packages

    puts "DEBUG: #{package_name}"
    puts "DEBUG: #{available_packages.include? package_name}"

    unless skip_available_packages || available_packages.include?(package_name)
      puts "Unknown package #{package_name}, use one of these: #{available_packages.sort}"
      exit 1
    end

    # TODO: fix prefix
    prefix = ''
    package_name = "#{prefix}#{package_name}"

    test_deb package_name: package_name, distribution: distribution, verbose: verbose, command: command
  end

  def update_aptly(distribution:, skip_upload: false)
    puts "Distribution: #{distribution}"
    puts 'DEBUG: @config.settings'
    pp @config.settings

    deb_path = File.join @config.output, distribution
    deb_abs_path = File.absolute_path deb_path

    repo = "#{@config.aptly_repo}-#{distribution}"

    begin
      result = @aptly.repo_create name: repo, default_distribution: distribution
      puts "Repo #{repo} created"
      puts result
    rescue Aptly::ExistsError
      puts "Repo #{repo} already exists"
    end

    upload_deb directory: deb_abs_path, repo: repo unless skip_upload
    update_repo repo: repo, distribution: distribution

    puts 'Done'
  end
end
