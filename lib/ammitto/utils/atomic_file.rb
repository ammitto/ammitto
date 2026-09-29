# frozen_string_literal: true

require 'fileutils'
require 'securerandom'

module Ammitto
  module Utils
    # Writes a file so that a reader sees either the old content or the new,
    # never a prefix of the new. Cache files are read back as JSON on every
    # search until their TTL expires, so an interrupted plain write would
    # leave a file that fails to parse for as long as it stays fresh.
    #
    # On POSIX the final step is rename(2), which replaces the destination
    # atomically. On Windows Ruby's File.rename over an existing file is an
    # unlink followed by a rename, so there is a moment with no file at all;
    # there the old file is moved aside first and moved back if the new one
    # cannot be put in place, so a failure never loses the previous content.
    # No fsync: this guards against interrupted writers, not power loss, and
    # a cache lost to a crash is simply downloaded again.
    module AtomicFile
      # Collisions on a random 64-bit name mean something other than chance
      # is creating these files; retrying forever would hang the caller.
      TEMP_ATTEMPTS = 10

      module_function

      # @param path [String] destination path
      # @param content [String] bytes to write
      # @return [void]
      def write(path, content)
        dir = File.dirname(path)
        FileUtils.mkdir_p(dir)
        mode = File.exist?(path) ? File.stat(path).mode & 0o7777 : 0o666 & ~File.umask
        tmp = create_temp(dir, File.basename(path), content)
        begin
          File.chmod(mode, tmp)
          replace(tmp, path)
          tmp = nil
        ensure
          FileUtils.rm_f(tmp) if tmp
        end
      end

      # Same directory as the destination, because rename is only atomic
      # within one filesystem. O_EXCL makes the name ours alone, so cleanup
      # can never remove a file another writer created.
      def create_temp(dir, base, content)
        TEMP_ATTEMPTS.times do
          tmp = File.join(dir, ".#{base}.#{SecureRandom.hex(8)}.tmp")
          begin
            File.open(tmp, File::WRONLY | File::CREAT | File::EXCL | File::BINARY, 0o600) do |file|
              file.write(content)
            end
          rescue Errno::EEXIST
            next
          rescue StandardError
            FileUtils.rm_f(tmp)
            raise
          end
          return tmp
        end
        raise CacheError.new(
          "Could not create a unique temp file next to #{File.join(dir, base)} " \
          "after #{TEMP_ATTEMPTS} attempts",
          path: File.join(dir, base)
        )
      end

      def replace(tmp, path)
        return File.rename(tmp, path) unless Gem.win_platform? && File.exist?(path)

        aside = "#{tmp}.old"
        File.rename(path, aside)
        begin
          File.rename(tmp, path)
        rescue StandardError => e
          restore_aside(aside, path, e)
          raise
        end
        FileUtils.rm_f(aside)
      end

      # The set-aside copy is the only surviving old content once both
      # renames fail, so it is left in place and named in the error.
      def restore_aside(aside, path, cause)
        File.rename(aside, path)
      rescue StandardError => e
        raise CacheError.new(
          "Could not move the new file into #{path} (#{cause.class}: #{cause.message}) " \
          "nor restore the previous one (#{e.class}: #{e.message}); " \
          "the previous content is kept at #{aside}",
          path: path
        )
      end
    end
  end
end
