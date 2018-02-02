require 'mkmf'
require 'syck'

module FPM
  module Cookery
    module InheritableAttr
      def attr_rw_list(*attrs)
        attrs.each do |attr|
          class_eval %{
              def self.#{attr}(*list)
                unless instance_variable_defined?(:@#{attr})
                  @#{attr} = InheritableAttr.inherit_for(self, :#{attr})
                end
                @#{attr} ||= []
                unless list.empty?
                  @#{attr} << list
                  @#{attr}.flatten!
                  @#{attr}.uniq!
                end
                @#{attr}
              end
              def self.#{attr}!(*list)
                @#{attr} = []
                unless list.empty?
                  @#{attr} << list
                  @#{attr}.flatten!
                  @#{attr}.uniq!
                end
                @#{attr}
              end
              def #{attr}
                self.class.#{attr}
              end
            }
        end

        register_attrs(:list, *attrs)
      end

      # Create +Hash+-style attributes.  Supports both hash and argument
      # assignment:
      #   attr_method[:attr1] = xxxx
      #   attr_method :xxxx=>1, :yyyy=>2
      def attr_rw_hash(*attrs)
        attrs.each do |attr|
          class_eval %{
            def self.#{attr}(args = {})
              unless instance_variable_defined?(:@#{attr})
                @#{attr} = InheritableAttr.inherit_for(self, :#{attr})
              end
              (@#{attr} ||= {}).merge!(args)
            end
            def self.#{attr}!(args = {})
              @#{attr} = {}
              @#{attr}.merge!(args)
            end
            def #{attr}
              self.class.#{attr}
            end
          }
        end

        register_attrs(:hash, *attrs)
      end

      # Create methods for attributes representing paths.  Arguments to
      # writer methods will be converted to +FPM::Cookery::Path+ objects.
      def attr_rw_path(*attrs)
        attrs.each do |attr|
          class_eval %{
            def self.#{attr}(value = nil)
              if value.nil?
                return @#{attr} if instance_variable_defined?(:@#{attr})
                @#{attr} = InheritableAttr.inherit_for(self, :#{attr})
              else
                @#{attr} = value
              end
            end
            def self.#{attr}=(value)
              @#{attr} = FPM::Cookery::Path.new(value)
            end
            def #{attr}=(value)
              self.class.#{attr} = value
            end
            def #{attr}(path = nil)
              self.class.#{attr}(path)
            end
          }
        end

        register_attrs(:path, *attrs)
      end
    end

    class SourceHandler
      class Curl
        def extract(_config = {})
          Dir.chdir(builddir) do
            case local_path.extname
            when '.bz2', '.gz', '.tgz', '.xz', '.tar', '.lz'
              tar = find_executable('bsdtar') ? 'bsdtar' : 'tar'
              safesystem(tar, 'xf', local_path)
            when '.shar', '.bin'
              File.chmod(0o755, local_path)
              safesystem(local_path)
            when '.zip'
              safesystem('unzip', '-d', local_path.basename('.zip'), local_path)
            when '.deb'
              safesystem('dpkg', '-x', local_path, local_path.basename('.deb'))
            else
              Dir.mkdir(local_path.basename) if !local_path.directory? && !local_path.basename.exist?

              FileUtils.cp_r(local_path, local_path.basename)
            end
            extracted_source
          end
        end
      end
    end

    class DependencyInspector
      def self.verify!(depends, build_depends)
        Puppet.initialize_settings unless defined?(Puppet::Resource)
        unless defined?(Puppet::Resource)
          Log.warn "Unable to load Puppet. Automatic dependency installation disabled."
          return
        end

        Log.info "Verifying build_depends and depends with Puppet"

        missing = missing_packages(build_depends + depends)

        if missing.length == 0
          Log.info "All build_depends and depends packages installed"
        else
          Log.info "Missing/wrong version packages: #{missing.join(', ')}"
          if Process.euid != 0
            Log.error "Not running as root; please run 'sudo fpm-cook install-deps' to install dependencies."
            exit 1
          else
            Log.info "Running as root; installing missing/wrong version build_depends and depends with Puppet"
            missing.each do |package|
              self.install_package(package)
            end
          end
        end
      end

      def self.package_installed?(package)
        Log.info("Verifying package: #{package}")
        return unless package_suitable?(package)

        # Use Puppet in noop mode to see if the package exists
        Puppet[:noop] = true
        resource = Puppet::Resource.new('package', package, parameters: {
                                          ensure: 'latest'
                                        })
        result = Puppet::Resource.indirection.save(resource)[1]
        !result.resource_statuses.values.first.out_of_sync
      end

      def self.install_package(package)
        Log.info("Installing package: #{package}")
        return unless package_suitable?(package)

        # Use Puppet to install a package
        Puppet[:noop] = false
        resource = Puppet::Resource.new('package', package, parameters: {
                                          ensure: 'latest'
                                        })
        result = Puppet::Resource.indirection.save(resource)[1]
        failed = result.resource_statuses.values.first.failed
        if failed
          Log.fatal "While processing depends package '#{package}':"
          result.logs.each { |log_line| Log.fatal log_line }
          exit 1
        else
          result.logs.each { |log_line| Log.info log_line }
        end
      end
    end
    module Utils
      protected

      # copy from make function
      def cmake(*args)
        env = args.pop if args.last.is_a?(Hash)
        env ||= {}

        args += env.map { |k, v| "#{k}=#{v}" }
        args.map!(&:to_s)

        safesystem 'cmake', *args
      end
    end
  end
end

Hiera::Fpm_cookery_logger = FPM::Cookery::Log::Hiera
