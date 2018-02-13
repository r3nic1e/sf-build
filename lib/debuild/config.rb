class Debuild
  attr_reader :config, :aptly

  class Config
    attr_reader :settings, :gitlab
    @settings = {}
    # TODO: change to global CI detection
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

    def apt_sources(distribution)
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

  @config = nil
  @use_release_config = false

  require_relative 'devel'
  require_relative 'release'
  def read_settings(*args, **kwargs)

    @config = (@use_release_config ? ReleaseConfig : DevelConfig).new(*args, **kwargs)
    @aptly = Aptly.new @config.aptly_api_url
  end
end
