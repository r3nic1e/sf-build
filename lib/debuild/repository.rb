class Debuild
  # @param [String] directory
  # @param [String] repo
  def upload_deb(directory:, repo:)
    deb_files = []
    Dir.open(directory).each do |f|
      path = File.join directory, f
      next unless File.file?(path) && (File.extname(path) == '.deb') && (!f.start_with? 'dummy')
      deb_files << path
    end

    puts "Found these packages: #{deb_files}"

    uploaded_files = @aptly.upload_upload directory: repo, files: deb_files
    puts "Uploaded files: [#{uploaded_files.join(', ')}]"

    @aptly.repo_add_packages_from_dir name: repo, dir: repo, force_replace: config.settings['aptly']['force_replace']
  end

  # @return [String]
  def create_repo
    repo = "#{@config.aptly_repo}-#{settings.distribution}"

    begin
      result = @aptly.repo_create name: repo, default_distribution: settings.distribution
      puts "Repo #{repo} created: #{result}"
    rescue Aptly::ExistsError
      puts "Repo #{repo} already exists"
    end

    repo
  end

  def publish_repo(repo:)
    result = @aptly.publish_create(
      source_kind: 'local', sources: [{ 'Component' => 'main', 'Name' => repo }],
      prefix: repo, distribution: settings.distribution,
      signing: @config.signing
    )
    puts "Repo #{repo} published with prefix #{repo}: #{result}"
  rescue Aptly::ExistsError
    puts "Repo #{repo} already published"
  end

  # @param [String] repo
  def update_repo(repo:)
    puts "DEBUG: updating aptly publish for repo #{repo} with distribution #{settings.distribution}"
    result = @aptly.publish_update prefix: repo, distribution: settings.distribution, force_overwrite: true, signing: @config.signing
    puts "DEBUG: #{result}"
  end
end
