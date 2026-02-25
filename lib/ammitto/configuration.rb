# frozen_string_literal: true

module Ammitto
  # Configuration class for Ammitto gem settings
  #
  # @example Basic configuration
  #   Ammitto.configure do |config|
  #     config.api_base_url = "https://www.ammitto.com/api/v1"
  #     config.cache_dir = File.expand_path("~/.ammitto")
  #     config.cache_ttl = 3600
  #   end
  #
  # @example Accessing configuration
  #   Ammitto.configuration.api_base_url
  #   # => "https://www.ammitto.com/api/v1"
  #
  class Configuration
    # @return [String] Base URL for the Ammitto API
    attr_accessor :api_base_url

    # @return [String] Directory for caching downloaded data
    attr_accessor :cache_dir

    # @return [Integer] Cache time-to-live in seconds
    attr_accessor :cache_ttl

    # @return [Integer] Connection timeout in seconds
    attr_accessor :connection_timeout

    # @return [Integer] Read timeout in seconds
    attr_accessor :read_timeout

    # @return [Boolean] Whether to enable verbose logging
    attr_accessor :verbose

    # @return [Logger] Custom logger instance
    attr_accessor :logger

    # @return [String] Directory for harmonized JSON-LD data repository
    attr_accessor :data_repository

    # @return [String] Parent directory for source data repositories
    attr_accessor :sources_dir

    # Default API base URL
    DEFAULT_API_BASE_URL = 'https://www.ammitto.com/api/v1'

    # Default cache directory
    DEFAULT_CACHE_DIR = File.expand_path('~/.ammitto')

    # Default cache TTL (1 hour)
    DEFAULT_CACHE_TTL = 3600

    # Default connection timeout (10 seconds)
    DEFAULT_CONNECTION_TIMEOUT = 10

    # Default read timeout (30 seconds)
    DEFAULT_READ_TIMEOUT = 30

    # Default data repository directory (../data from project root, not gem root)
    # __dir__ is lib/ammitto, so we go up 3 levels then into data
    DEFAULT_DATA_REPOSITORY = File.expand_path('../../../data', __dir__)

    # Default sources directory (parent of gem directory where data-* repos live)
    # __dir__ is lib/ammitto, so we go up 3 levels: lib/ammitto -> lib -> ammitto(gem) -> ammitto(project)
    DEFAULT_SOURCES_DIR = File.expand_path('../../..', __dir__)

    # Initialize configuration with defaults
    def initialize
      @api_base_url = DEFAULT_API_BASE_URL
      @cache_dir = DEFAULT_CACHE_DIR
      @cache_ttl = DEFAULT_CACHE_TTL
      @connection_timeout = DEFAULT_CONNECTION_TIMEOUT
      @read_timeout = DEFAULT_READ_TIMEOUT
      @verbose = false
      @logger = nil
      @data_repository = DEFAULT_DATA_REPOSITORY
      @sources_dir = DEFAULT_SOURCES_DIR
    end

    # @return [String] Full path to the cache sources directory
    def cache_sources_dir
      File.join(cache_dir, 'cache', 'sources')
    end

    # @return [String] Full path to the cache metadata file
    def cache_metadata_path
      File.join(cache_dir, 'metadata.json')
    end

    # Reset configuration to defaults
    # @return [void]
    def reset!
      @api_base_url = DEFAULT_API_BASE_URL
      @cache_dir = DEFAULT_CACHE_DIR
      @cache_ttl = DEFAULT_CACHE_TTL
      @connection_timeout = DEFAULT_CONNECTION_TIMEOUT
      @read_timeout = DEFAULT_READ_TIMEOUT
      @verbose = false
      @logger = nil
      @data_repository = DEFAULT_DATA_REPOSITORY
      @sources_dir = DEFAULT_SOURCES_DIR
    end
  end

  # Module-level configuration methods
  class << self
    # Get the current configuration
    # @return [Configuration] the current configuration
    def configuration
      @configuration ||= Configuration.new
    end

    # Configure Ammitto
    # @yield [Configuration] the configuration object
    # @return [void]
    # @example
    #   Ammitto.configure do |config|
    #     config.cache_ttl = 7200
    #   end
    def configure
      yield(configuration) if block_given?
    end

    # Reset configuration to defaults
    # @return [void]
    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
