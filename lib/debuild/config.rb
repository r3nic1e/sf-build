class Debuild
  # @!attribute [r] config
  #   @return [Debuild::Config]
  attr_reader :config, :aptly

  # @abstract
  class Config
    attr_reader :settings, :gitlab
    @settings = {}
    # @todo change to global CI detection
    @gitlab = false

    def timestamp
      @timestamp
    end

    def update_timestamp
      @timestamp = Time.now.to_i
    end

    def image_name(release: false)
      @settings['image']['name']
    end

    def aptly_repo
      @settings['aptly']['repo']
    end

    def aptly_repo_url
      @settings['aptly']['repo_url']
    end

    def aptly_api_url
      @settings['aptly']['api_url']
    end

    def apt_sources
      distribution = Debuild::Settings.instance.distribution
      [
        "deb [arch=amd64] #{@settings['aptly']['repo_url']}/#{@settings['aptly']['repo']}-#{distribution} #{distribution} main"
      ]
    end

    def output
      @settings['output']
    end

    def container
      @settings['container']
    end

    def data_container
      @settings['data_container']
    end

    def signing
      @settings['aptly']['signing']
    end

    def snapshot_prefix
      @settings['aptly']['snapshot_prefix']
    end

    # @return [Array]
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

  def test(package_name:, skip_available_packages: false, command: nil)
    available_packages = packages

    puts "DEBUG: #{package_name}"
    puts "DEBUG: #{available_packages.include? package_name}"

    unless skip_available_packages || available_packages.include?(package_name)
      puts "Unknown package #{package_name}, use one of these: #{available_packages.sort}"
      exit 1
    end

    # @todo fix prefix
    prefix = ''
    package_name = "#{prefix}#{package_name}"

    test_deb package_name: package_name, command: command
  end

  @config = nil

  require_relative 'devel'
  require_relative 'release'
  def read_settings(*args, **kwargs)
    @config = (settings.release ? ReleaseConfig : DevelConfig).new(*args, **kwargs)
    @aptly = Aptly.new @config.aptly_api_url
  end
end
