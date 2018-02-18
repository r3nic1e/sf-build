# @!attribute [r] config
#   @return [Debuild::Config]
# @!attribute [r] aptly
#   @return [Aptly]
class Debuild
  attr_reader :config, :aptly

  # Abstract class to contain some predefined variables via config files
  # @see ReleaseConfig
  # @see DevelConfig
  #
  # @abstract
  # @!attribute [r] settings
  #   @return [Hash]
  # @!attribute [r] gitlab
  #   @return [Boolean]
  class Config
    attr_reader :settings, :gitlab
    @settings = {}
    # @todo change to global CI detection
    @gitlab = false

    # Get current saved timestamp
    # Used as caching key
    #
    # @return [Integer]
    def timestamp
      @timestamp
    end

    # Update saved timestamp
    def update_timestamp
      @timestamp = Time.now.to_i
    end

    # Get base image name
    #
    # @return [String]
    def image_name(*)
      @settings['image']['name']
    end

    # Get aptly repository
    #
    # @return [String]
    def aptly_repo
      @settings['aptly']['repo']
    end

    # Get base aptly URL
    #
    # @return [String]
    def aptly_repo_url
      @settings['aptly']['repo_url']
    end

    # Get base aptly API URL
    #
    # @return [String]
    def aptly_api_url
      @settings['aptly']['api_url']
    end

    # Get rendered apt sources
    #
    # @return [Array<String>]
    def apt_sources
      distribution = Debuild::Settings.instance.distribution
      [
        "deb [arch=amd64] #{@settings['aptly']['repo_url']}/#{@settings['aptly']['repo']}-#{distribution} #{distribution} main"
      ]
    end

    # Get built packages format
    #
    # @return [String]
    def output
      @settings['output']
    end

    # Get base container name
    #
    # @return [String]
    def container
      @settings['container']
    end

    # Get base data container name
    #
    # @return [String]
    def data_container
      @settings['data_container']
    end

    # Get aptly signing options
    #
    # @return [Hash]
    def signing
      @settings['aptly']['signing']
    end

    # Get aptly snapshot prefix
    # @return [String]
    def snapshot_prefix
      @settings['aptly']['snapshot_prefix']
    end

    # Get available packages paths
    #
    # @return [Array<String>]
    def packages(basedir: Dir.pwd)
      packages = []
      recipes_dir = File.join basedir, 'recipes'
      Dir.open(recipes_dir).each do |f|
        path = File.join recipes_dir, f
        next unless File.directory? path

        recipe_file = File.join path, 'recipe.rb'
        next unless File.file? recipe_file

        packages << f
      end

      packages
    end
  end

  require_relative 'devel'
  require_relative 'release'

  # Read config file and initialize Aptly instance
  # @see ReleaseConfig
  # @see DevelConfig
  def read_settings(*args, **kwargs)
    @config = (settings.release ? ReleaseConfig : DevelConfig).new(*args, **kwargs)
    @aptly = Aptly.new @config.aptly_api_url
  end
end
