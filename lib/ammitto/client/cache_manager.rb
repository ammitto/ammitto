# frozen_string_literal: true

require 'json'

module Ammitto
  module Client
    # CacheManager manages cache refresh and status
    #
    # @example Refreshing cache
    #   CacheManager.refresh(sources: [:eu, :un])
    #   CacheManager.refresh(all: true)
    #
    # @example Checking status
    #   status = CacheManager.status
    #   # => { eu: { cached: true, ... }, ... }
    #
    class CacheManager
      class << self
        # Refresh cache for specified sources
        # @param options [Hash] refresh options
        # @option options [Array<Symbol>] :sources list of sources to refresh
        # @option options [Boolean] :all refresh all sources
        # @option options [Boolean] :force force refresh even if cache is fresh
        # @return [Hash] status of each source refresh
        def refresh(options = {})
          sources = determine_sources(options)
          force = options[:force]
          results = {}

          sources.each do |code|
            results[code] = refresh_source(code, force: force)
          end

          save_metadata
          results
        end

        # Get cache status for all sources
        # @return [Hash] status of each cached source
        def status
          cache = Cache.new
          results = {}

          Registry.codes.each do |code|
            info = cache.info(code)
            results[code] = if info
                              {
                                cached: true,
                                updated_at: info[:modified],
                                size: info[:size],
                                age_seconds: info[:age_seconds]
                              }
                            else
                              { cached: false }
                            end
          end

          results
        end

        # Get metadata about the cache
        # @return [Hash, nil] cache metadata
        def metadata
          path = Ammitto.configuration.cache_metadata_path
          return nil unless File.exist?(path)

          content = File.read(path)
          MultiJson.load(content)
        rescue JSON::ParserError
          nil
        end

        private

        # Determine which sources to refresh
        # @param options [Hash] the options
        # @return [Array<Symbol>] list of source codes
        def determine_sources(options)
          if options[:all]
            Registry.codes
          elsif options[:sources]
            Array(options[:sources]).map(&:to_sym)
          else
            Registry.codes
          end
        end

        # Refresh a single source
        # @param code [Symbol] the source code
        # @param force [Boolean] force refresh
        # @return [Hash] refresh result
        def refresh_source(code, force: false)
          cache = Cache.new

          return { status: :cached, message: 'Cache is fresh' } if !force && cache.exists?(code)

          begin
            client = ApiClient.new
            data = client.fetch_source(code)
            cache.write(code, data)
            { status: :refreshed, message: 'Cache updated' }
          rescue NetworkError => e
            Logger.error("Failed to refresh #{code}: #{e.message}")
            { status: :error, message: e.message }
          rescue StandardError => e
            Logger.error("Failed to refresh #{code}: #{e.message}")
            { status: :error, message: e.message }
          end
        end

        # Save cache metadata
        # @return [void]
        def save_metadata
          path = Ammitto.configuration.cache_metadata_path
          data = {
            version: VERSION,
            updated_at: Time.now.utc.iso8601,
            sources: status
          }

          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, MultiJson.dump(data, pretty: true))
        end
      end
    end
  end
end
