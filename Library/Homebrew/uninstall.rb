# typed: true
# frozen_string_literal: true

require "installed_dependents"

module Homebrew
  # Helper module for uninstalling kegs.
  #
  # @api private
  module Uninstall
    def self.uninstall_kegs(kegs_by_rack, casks: [], force: false, ignore_dependencies: false, named_args: [])
      handle_unsatisfied_dependents(kegs_by_rack,
                                    casks:,
                                    ignore_dependencies:,
                                    named_args:)
      return if Homebrew.failed?

      kegs_by_rack.each do |rack, kegs|
        if force
          name = rack.basename

          if rack.directory?
            puts "Uninstalling #{name}... (#{rack.abv})"
            kegs.each do |keg|
              keg.unlink
              keg.uninstall
            end
          end

          rm_pin rack
        else
          kegs.each do |keg|
            begin
              f = Formulary.from_rack(rack)
              if f.pinned?
                onoe "#{f.full_name} is pinned. You must unpin it to uninstall."
                break # exit keg loop and move on to next rack
              end
            rescue
              nil
            end

            keg.lock do
              puts "Uninstalling #{keg}... (#{keg.abv})"
              keg.unlink
              keg.uninstall
              rack = keg.rack
              rm_pin rack

              if rack.directory?
                versions = rack.subdirs.map(&:basename)
                puts <<~EOS
                  #{keg.name} #{versions.to_sentence} #{(versions.count == 1) ? "is" : "are"} still installed.
                  To remove all versions, run:
                    brew uninstall --force #{keg.name}
                EOS
              end

              next unless f

              paths = f.pkgetc.find.map(&:to_s) if f.pkgetc.exist?
              if paths.present?
                puts
                opoo <<~EOS
                  The following #{f.name} configuration files have not been removed!
                  If desired, remove them manually with `rm -rf`:
                    #{paths.sort.uniq.join("\n  ")}
                EOS
              end

              unversioned_name = f.name.gsub(/@.+$/, "")
              maybe_paths = Dir.glob("#{f.etc}/*#{unversioned_name}*")
              maybe_paths -= paths if paths.present?
              if maybe_paths.present?
                puts
                opoo <<~EOS
                  The following may be #{f.name} configuration files and have not been removed!
                  If desired, remove them manually with `rm -rf`:
                    #{maybe_paths.sort.uniq.join("\n  ")}
                EOS
              end
            end
          end
        end
      end
    rescue MultipleVersionsInstalledError => e
      ofail e
    ensure
      # If we delete Cellar/newname, then Cellar/oldname symlink
      # can become broken and we have to remove it.
      if HOMEBREW_CELLAR.directory?
        HOMEBREW_CELLAR.children.each do |rack|
          rack.unlink if rack.symlink? && !rack.resolved_path_exists?
        end
      end
    end

    def self.handle_unsatisfied_dependents(kegs_by_rack, casks: [], ignore_dependencies: false, named_args: [])
      return if ignore_dependencies

      all_kegs = kegs_by_rack.values.flatten(1)
      return unless (result = InstalledDependents.find_some_installed_dependents(all_kegs, casks:))

      DependentsMessage.new(*result, named_args:).output
      nil
    rescue MethodDeprecatedError
      # Silently ignore deprecations when uninstalling.
      nil
    end

    # @api private
    class DependentsMessage
      attr_reader :reqs, :deps, :named_args

      def initialize(requireds, dependents, named_args: [])
        @reqs = requireds
        @deps = dependents
        @named_args = named_args
      end

      def output
        ofail <<~EOS
          Refusing to uninstall #{reqs.to_sentence}
          because #{reqs_are_required_by_deps}.
          You can override this and force removal with:
            #{sample_uninstall_command}
          If you need to reinstall #{(reqs.count == 1) ? "it" : "them"}, run:
            #{sample_reinstall_command}
        EOS
      end

      private

      def reqs_are_required_by_deps
        "#{(reqs.count == 1) ? "it is" : "they are"} required by #{deps.to_sentence}, " \
          "which #{(deps.count == 1) ? "is" : "are"} currently installed"
      end

      def sample_uninstall_command
        "brew uninstall --ignore-dependencies #{named_args.join(" ")}"
      end

      def sample_reinstall_command
        "brew reinstall #{named_args.join(" ")}"
      end
    end

    def self.rm_pin(rack)
      Formulary.from_rack(rack).unpin
    rescue
      nil
    end
  end
end
