class Debuild
  attr_reader :config, :aptly

  class Config
    attr_reader :settings, :gitlab

    def initialize(settings: {}, release_settings: {}, use_release_images: false)
      update_timestamp
      @gitlab = ENV['CI_BUILD_REF_NAME']

      @settings = settings
      @release_settings = release_settings

      @use_release_images = use_release_images
    end

    def timestamp
      @timestamp
    end

    def update_timestamp
      @timestamp = Time.now.to_i
    end

    def image_name(release: false)
      if release || @use_release_images
        @release_settings['image']['name']
      else
        @settings['image']['name']
      end
    end

    def aptly_repo(release: false)
      @settings['aptly']['repo']
    end

    def aptly_repo_url(release: false)
      @settings['aptly']['repo_url']
    end

    def aptly_api_url(release: false)
      @settings['aptly']['api_url']
    end

    def apt_sources(distribution)
      sources = [
        "deb [arch=amd64] #{@release_settings['aptly']['repo_url']}/#{@release_settings['aptly']['repo']}-#{distribution} #{distribution} main",
        "deb [arch=amd64] #{@settings['aptly']['repo_url']}/#{@settings['aptly']['repo']}-#{distribution} #{distribution} main"
      ]

      sources.uniq
    end

    def output(release: false)
      @settings['output']
    end

    def container(release: false)
      @settings['container']
    end

    def data_container(release: false)
      @settings['data_container']
    end

    def signing(release: false)
      @settings['aptly']['signing']
    end

    def snapshot_prefix(release: false)
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

  def create_config(settings: {}, release_settings: {}, use_release_images: false)
    @config = Config.new(settings: settings, release_settings: release_settings, use_release_images: use_release_images)
  end
end
