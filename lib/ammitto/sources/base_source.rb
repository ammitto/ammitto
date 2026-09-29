# frozen_string_literal: true

require 'fileutils'
require 'securerandom'

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
  #       "https://www.ammitto.org/api/v1/sources/eu.jsonld"
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

      stat = nil
      content = File.open(path, 'rb') do |file|
        stat = file.stat
        file.read
      end
      MultiJson.load(content)
    rescue MultiJson::ParseError => e
      # A file that does not parse would otherwise be served until its TTL
      # expires, failing every search that includes this source. Removing
      # it lets the next call download afresh, and CacheError lets the
      # search skip this one source instead of aborting.
      remove_if_unchanged(path, stat)
      raise CacheError.new(
        "Cached #{code} data at #{path} is not valid JSON: #{e.message}",
        path: path
      )
    end

    # Another process may install a good file at any moment, so the entry
    # is first renamed to a private quarantine name and its identity is
    # checked there, where no other writer can replace it. Only the file
    # that was read is ever deleted; anything else is linked back, and
    # the link fails rather than overwrite a file that arrived since.
    # Windows reports no inode, so size and mtime stand in for identity.
    def remove_if_unchanged(path, read_stat)
      return unless same_file?(File.stat(path), read_stat)

      name = "#{path}.#{SecureRandom.hex(8)}.corrupt"
      File.rename(path, name)
      quarantine = name
      return if same_file?(File.stat(quarantine), read_stat)

      File.link(quarantine, path)
    rescue Errno::ENOENT, Errno::EEXIST
      nil
    ensure
      # On EEXIST a newer file already holds the path, so the quarantined
      # one is stale and would otherwise pile up beside the cache forever.
      # Set only after the rename, so a failed rename never deletes a name
      # this call does not own.
      FileUtils.rm_f(quarantine) if quarantine
    end
    private :remove_if_unchanged

    def same_file?(current, read_stat)
      keys = Gem.win_platform? ? %i[size mtime] : %i[dev ino size mtime]
      keys.all? { |k| current.public_send(k) == read_stat.public_send(k) }
    end
    private :same_file?

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

      # A transport failure has to arrive as NetworkError like every
      # other download failure. QueryBuilder#execute rescues NetworkError
      # so that one unreachable source cannot take a whole search down —
      # its own comment says so — but Faraday raises its own error class
      # from underneath, which slipped past that rescue and killed the
      # call. On a cold cache with no network, `Ammitto.search` died with
      # Faraday::ConnectionFailed instead of returning what it could.
      begin
        # Use ApiClient's connection so the configured timeouts apply here too
        response = Client::ApiClient.new.connection.get(api_endpoint)
      rescue Faraday::Error => e
        raise NetworkError.new(
          "Failed to download #{code} data: #{e.message}",
          url: api_endpoint
        )
      end

      unless response.success?
        raise NetworkError.new(
          "Failed to download #{code} data",
          status_code: response.status,
          url: api_endpoint
        )
      end

      Utils::AtomicFile.write(cache_path, response.body)

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
