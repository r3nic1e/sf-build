require 'yaml'
require_relative 'build'
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
    def initialize(image_suffix: '-devel', skip_devel: false)
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
      @use_release_images = Debuild::Settings.instance.use_release_images

      @aptly = Aptly.new aptly_api_url
    end

    def image_name(release: false)
      if release || @use_release_images
        @release_settings['image']['name']
      else
        @settings['image']['name']
      end
    end

    def apt_sources
      distribution = Debuild::Settings.instance.distribution
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
