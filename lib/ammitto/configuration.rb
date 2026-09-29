# frozen_string_literal: true

require_relative 'config/defaults'
require_relative 'config/env_provider'

module Ammitto
  # Configuration class for Ammitto gem settings
  #
  # @example Basic configuration
  #   Ammitto.configure do |config|
  #     config.api_base_url = "https://www.ammitto.org/api/v1"
  #     config.cache_dir = File.expand_path("~/.ammitto")
  #     config.cache_ttl = 3600
  #   end
  #
  # @example Accessing configuration
  #   Ammitto.configuration.api_base_url
  #   # => "https://www.ammitto.org/api/v1"
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

    # @return [Symbol] Parse-failure visibility mode (:raise, :warn, :silent)
    attr_accessor :parse_failure_mode

    # @return [String] Directory for harmonized JSON-LD data repository
    attr_accessor :data_repository

    # @return [String] Parent directory for source data repositories
    attr_accessor :sources_dir

    # Default API base URL (single source of truth: Config::Defaults —
    # www.ammitto.com serves no API)
    DEFAULT_API_BASE_URL = Config::Defaults::API_BASE_URL

    # Default cache directory
    DEFAULT_CACHE_DIR = Config::Defaults::CACHE_DIR

    # Default cache TTL (1 hour)
    DEFAULT_CACHE_TTL = Config::Defaults::CACHE_TTL

    # Default connection timeout (10 seconds)
    DEFAULT_CONNECTION_TIMEOUT = Config::Defaults::CONNECTION_TIMEOUT

    # Default read timeout (30 seconds)
    DEFAULT_READ_TIMEOUT = Config::Defaults::READ_TIMEOUT

    # Default data repository directory (../data from project root, not gem root)
    DEFAULT_DATA_REPOSITORY = Config::Defaults::DATA_REPOSITORY

    # Default sources directory (parent of gem directory where data-* repos live)
    DEFAULT_SOURCES_DIR = Config::Defaults::SOURCES_DIR

    # Keys the environment may set, so a documented AMMITTO_* variable
    # reaches every reader of this object and not only the CLI
    ENV_KEYS = %i[api_base_url cache_dir cache_ttl connection_timeout read_timeout
                  verbose parse_failure_mode data_repository sources_dir].freeze

    # Initialize configuration from defaults, then the environment
    def initialize
      reset!
    end

    # @return [String] Full path to the cache sources directory
    def cache_sources_dir
      File.join(cache_dir, 'cache', 'sources')
    end

    # @return [String] Full path to the cache metadata file
    def cache_metadata_path
      File.join(cache_dir, 'metadata.json')
    end

    # Reset configuration to defaults, then re-read the environment.
    # The environment is read here, once, so a later assignment through
    # Ammitto.configure still wins over it.
    # @return [void]
    def reset!
      @api_base_url = DEFAULT_API_BASE_URL
      @cache_dir = DEFAULT_CACHE_DIR
      @cache_ttl = DEFAULT_CACHE_TTL
      @connection_timeout = DEFAULT_CONNECTION_TIMEOUT
      @read_timeout = DEFAULT_READ_TIMEOUT
      @verbose = Config::Defaults::VERBOSE
      @logger = nil
      @parse_failure_mode = Config::Defaults::PARSE_FAILURE_MODE
      @data_repository = DEFAULT_DATA_REPOSITORY
      @sources_dir = DEFAULT_SOURCES_DIR
      apply_environment
    end

    private

    def apply_environment
      Config::EnvProvider.configuration.slice(*ENV_KEYS).each do |key, value|
        value = File.expand_path(value) if key == :cache_dir
        instance_variable_set(:"@#{key}", value)
      end
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
