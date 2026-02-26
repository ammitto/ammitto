# frozen_string_literal: true

require 'fileutils'
require 'json'

module Ammitto
  module Client
    # Cache manages local caching of sanction data
    #
    # @example Using the cache
    #   cache = Cache.new
    #   cache.write(:eu, data)
    #   data = cache.read(:eu)
    #
    class Cache
      # @return [String] the cache directory
      attr_reader :cache_dir

      # Initialize the cache
      # @param cache_dir [String, nil] custom cache directory
      def initialize(cache_dir = nil)
        @cache_dir = cache_dir || Ammitto.configuration.cache_dir
        ensure_cache_dir
      end

      # Read data from cache
      # @param source_code [Symbol] the source code
      # @return [Hash, nil] the cached data or nil
      def read(source_code)
        path = source_path(source_code)
        return nil unless File.exist?(path)

        content = File.read(path)
        MultiJson.load(content)
      rescue JSON::ParserError => e
        Logger.error("Failed to parse cache for #{source_code}: #{e.message}")
        nil
      end

      # Write data to cache
      # @param source_code [Symbol] the source code
      # @param data [Hash] the data to cache
      # @return [void]
      def write(source_code, data)
        path = source_path(source_code)
        File.write(path, MultiJson.dump(data, pretty: true))
        Logger.debug("Cached #{source_code} data to #{path}")
      end

      # Check if cache exists and is fresh
      # @param source_code [Symbol] the source code
      # @param max_age [Integer, nil] maximum age in seconds
      # @return [Boolean]
      def exists?(source_code, max_age = nil)
        path = source_path(source_code)
        return false unless File.exist?(path)

        max_age ||= Ammitto.configuration.cache_ttl
        age = Time.now - File.mtime(path)
        age < max_age
      end

      # Get cache info for a source
      # @param source_code [Symbol] the source code
      # @return [Hash, nil] cache info or nil
      def info(source_code)
        path = source_path(source_code)
        return nil unless File.exist?(path)

        stat = File.stat(path)
        {
          source: source_code,
          path: path,
          size: stat.size,
          modified: stat.mtime.iso8601,
          age_seconds: (Time.now - stat.mtime).to_i
        }
      end

      # Clear cache for a source
      # @param source_code [Symbol] the source code
      # @return [Boolean] true if deleted
      def clear(source_code)
        path = source_path(source_code)
        return false unless File.exist?(path)

        File.delete(path)
        Logger.info("Cleared cache for #{source_code}")
        true
      end

      # Clear all cache
      # @return [void]
      def clear_all
        sources_dir = File.join(cache_dir, 'cache', 'sources')
        return unless Dir.exist?(sources_dir)

        Dir.glob(File.join(sources_dir, '*.jsonld')).each do |file|
          File.delete(file)
        end

        Logger.info('Cleared all cache')
      end

      # Get path for a source cache file
      # @param source_code [Symbol] the source code
      # @return [String] the file path
      def source_path(source_code)
        File.join(cache_dir, 'cache', 'sources', "#{source_code}.jsonld")
      end

      private

      # Ensure cache directory exists
      def ensure_cache_dir
        sources_dir = File.join(cache_dir, 'cache', 'sources')
        FileUtils.mkdir_p(sources_dir)
      rescue Errno::EACCES => e
        raise CacheError.new(
          "Cannot create cache directory: #{e.message}",
          path: sources_dir
        )
      end
    end
  end
end
