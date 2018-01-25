class Aptly
  class NoPackagesError < StandardError
  end
  class DependencyError < StandardError
  end
  class ExistsError < StandardError
  end
  class NotExistsError < StandardError
  end
  class Exception < StandardError
  end
end
