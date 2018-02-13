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
  class DevelConfig < Config
    def initialize(image_suffix: '-devel', skip_devel: false, use_release_images: false)
      release_settings = YAML.load_file 'release.yml'

      begin
        devel_settings = YAML.load_file 'devel.yml'
      rescue StandardError => e
        unless skip_devel
          pp e
          puts 'Failed to read devel.yml, beware possible production corruption'
          exit 1
        end
      end

      check_settings_consistency(devel_settings, release_settings)

      settings = release_settings.deep_dup.deep_merge devel_settings

      settings['image']['name'] += image_suffix if image_suffix

      update_timestamp

      @settings = settings
      @release_settings = release_settings
      @use_release_images = use_release_images

      @aptly = Aptly.new aptly_api_url
    end

    def test(package_name:, distribution:, verbose: false, skip_available_packages: false, command: nil)
      read_settings image_suffix: '-test'

      available_packages = packages

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

      deb_path = File.join output, distribution
      deb_abs_path = File.absolute_path deb_path

      repo = "#{aptly_repo}-#{distribution}"

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

    def image_name(release: false)
      if release || @use_release_images
        @release_settings['image']['name']
      else
        @settings['image']['name']
      end
    end

    def apt_sources(distribution)
      [
        "deb [arch=amd64] #{@release_settings['aptly']['repo_url']}/#{@release_settings['aptly']['repo']}-#{distribution} #{distribution} main",
        "deb [arch=amd64] #{@settings['aptly']['repo_url']}/#{@settings['aptly']['repo']}-#{distribution} #{distribution} main"
      ]
    end

    private

    def check_settings_consistency(devel_settings, release_settings)
      unless devel_settings.key?('aptly') && devel_settings['aptly'].key?('repo')
        puts "No 'aptly.repo' section in devel.yml"
        exit 1
      end

      if devel_settings['aptly']['repo'] == release_settings['aptly']['repo']
        puts "Bad 'aptly.repo' section in devel.yml"
        exit 1
      end
    end
  end
end
