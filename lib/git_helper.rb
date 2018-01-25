# @return [Array]
def get_git_changes(path)
  release_commit = 'HEAD'
  output = `git log --no-color --pretty=format:%P --max-count=1 #{release_commit}`
  puts "GIT LOG PARENTS:\n#{output}\n"

  commits = output.chomp.split

  if commits.length > 2
    # not supporting more than 2 parents
    puts 'More than 2 parents -> not implemented'
    exit 1
  end

  if commits.length == 2
    # we got merge commit - need to go for parent
    release_commit = commits[1]
  end

  # get info for release commit
  output = `git log --no-merges --no-color --pretty=oneline --name-only --max-count=1 #{release_commit}`
  puts "GIT LOG (#{release_commit}):\n#{output}\n"

  lines = output.chomp.split
  lines.shift

  # process release commit
  files = lines.map { |l| l.split[-1] }
  changed = files.select { |f| f.start_with? path }

  changed
end
