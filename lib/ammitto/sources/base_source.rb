# frozen_string_literal: true

module Ammitto
  # BaseSource is the abstract base class for all data sources
  #
  # Each source (EU, UN, US, etc.) should inherit from this class
  # and implement the required methods.
  #
  # @example Creating a source
  #   class EuSource < BaseSource
  #     def code
  #       :eu
  #     end
  #
  #     def authority
  #       Authority.find("eu")
  #     end
  #
  #     def api_endpoint
  #       "https://www.ammitto.com/api/v1/sources/eu.jsonld"
  #     end
  #   end
  #
  class BaseSource
    # Get the source code
    # @return [Symbol] the source code
    def code
      raise NotImplementedError, 'Subclasses must implement #code'
    end

    # Get the authority for this source
    # @return [Authority] the authority
    def authority
      raise NotImplementedError, 'Subclasses must implement #authority'
    end

    # Get the API endpoint for this source
    # @return [String] the endpoint URL
    def api_endpoint
      "#{Ammitto.configuration.api_base_url}/sources/#{code}.jsonld"
    end

    # Get the local cache path for this source
    # @return [String] the cache file path
    def cache_path
      File.join(Ammitto.configuration.cache_sources_dir, "#{code}.jsonld")
    end

    # Parse JSON-LD data from the cache
    # @return [Hash] the parsed data
    def parse_cached_data
      path = cache_path
      return nil unless File.exist?(path)

      content = File.read(path)
      MultiJson.load(content)
    end

    # Load data from cache or API
    # @param force [Boolean] force refresh from API
    # @return [Hash] the loaded data
    def load_data(force: false)
      download_to_cache if force || !cache_exists?

      parse_cached_data
    end

    # Check if cache exists and is fresh
    # @return [Boolean]
    def cache_exists?
      path = cache_path
      return false unless File.exist?(path)

      # Check cache TTL
      mtime = File.mtime(path)
      age = Time.now - mtime
      age < Ammitto.configuration.cache_ttl
    end

    # Download data from API to cache
    # @return [void]
    def download_to_cache
      require 'fileutils'

      # Ensure cache directory exists
      dir = File.dirname(cache_path)
      FileUtils.mkdir_p(dir)

      # Download from API
      response = Faraday.get(api_endpoint)

      unless response.success?
        raise NetworkError.new(
          "Failed to download #{code} data",
          status_code: response.status,
          url: api_endpoint
        )
      end

      # Write to cache
      File.write(cache_path, response.body)

      Logger.info("Downloaded #{code} data to #{cache_path}")
    end

    # Search for entities matching a term
    # @param term [String] the search term
    # @param data [Hash] the source data
    # @return [Array<Hash>] matching entities
    def search(term, data)
      return [] unless data && data['@graph']

      term_lower = term.downcase

      data['@graph'].select do |item|
        # Search in names
        names = item['names'] || []
        names.any? do |name|
          name.is_a?(Hash) ? matches_name?(name, term_lower) : name.to_s.downcase.include?(term_lower)
        end
      end
    end

    # Check if a name matches a search term
    # @param name [Hash] the name data
    # @param term [String] the lowercase search term
    # @return [Boolean]
    def matches_name?(name, term)
      fields = %w[fullName firstName lastName middleName]
      fields.any? do |field|
        value = name[field]
        value&.downcase&.include?(term)
      end
    end

    # Get cache metadata for this source
    # @return [Hash, nil]
    def cache_metadata
      return nil unless File.exist?(cache_path)

      {
        path: cache_path,
        size: File.size(cache_path),
        modified: File.mtime(cache_path).iso8601
      }
    end
  end
end
