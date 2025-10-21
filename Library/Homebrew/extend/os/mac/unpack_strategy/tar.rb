# typed: strict
# frozen_string_literal: true

require "system_command"

module UnpackStrategy
  class Tar
    module MacOSTarExtension
      extend T::Helpers

      requires_ancestor { UnpackStrategy }

      private

      sig { params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).void }
      def extract_to_dir(unpack_dir, basename:, verbose:)
        # Use ditto with APFS/HFS+ compression if enabled
        if Homebrew::EnvConfig.install_compressed?
          # Extract to a temporary directory first, then copy with compression
          Dir.mktmpdir("homebrew-tar-compressed", HOMEBREW_TEMP) do |tmp_unpack_dir|
            tmp_unpack_dir = Pathname(tmp_unpack_dir)

            # Extract normally to temp directory using the parent implementation
            super(tmp_unpack_dir, basename:, verbose:)

            # Now copy with HFS+ compression using ditto
            tmp_unpack_dir.children.each do |child|
              system_command! "ditto",
                              args:    ["--hfsCompression", child, unpack_dir/child.basename],
                              verbose:
            end
          end
        else
          # Fall back to the standard tar extraction
          super
        end
      end
    end
    private_constant :MacOSTarExtension

    prepend MacOSTarExtension
  end
end
