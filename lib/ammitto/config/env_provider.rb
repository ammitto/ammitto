# frozen_string_literal: true

module Ammitto
  module Config
    # ENV variable provider for Ammitto configuration
    #
    # Reads configuration from environment variables with AMMITTO_ prefix.
    # Environment variables take highest priority in the configuration chain.
    #
    # Supported environment variables:
    #   AMMITTO_CACHE_DIR - Directory for caching data
    #   AMMITTO_SOURCES_DIR - Parent directory containing data-* repos
    #     (AMMITTO_DATA_DIR is honored as an alias; the CI validation
    #     scripts use that name for the same directory)
    #   AMMITTO_API_BASE_URL - Base URL for API
    #   AMMITTO_LOG_LEVEL - Log level (debug, info, warn, error)
    #   AMMITTO_SOURCES - Comma-separated list of sources
    #   AMMITTO_OUTPUT_FORMAT - Output format (jsonld, ttl, nt, rdfxml)
    #   AMMITTO_CONNECTION_TIMEOUT - HTTP connection timeout
    #   AMMITTO_READ_TIMEOUT - HTTP read timeout
    #   AMMITTO_VERBOSE - Enable verbose output (true/false)
    #
    class EnvProvider
      # ENV variable prefix
      PREFIX = 'AMMITTO_'

      # Map option names to ENV variable names
      ENV_MAPPING = {
        cache_dir: 'CACHE_DIR',
        api_base_url: 'API_BASE_URL',
        log_level: 'LOG_LEVEL',
        sources: 'SOURCES',
        output_format: 'OUTPUT_FORMAT',
        connection_timeout: 'CONNECTION_TIMEOUT',
        read_timeout: 'READ_TIMEOUT',
        verbose: 'VERBOSE',
        data_repository: 'DATA_REPOSITORY',
        sources_dir: 'SOURCES_DIR'
      }.freeze

      # Fallback ENV names consulted when the primary variable is unset
      ENV_ALIASES = { sources_dir: 'DATA_DIR' }.freeze

      class << self
        # Check if any Ammitto ENV variable carries a usable value
        #
        # Mirrors {configuration}: variables set to an empty string are
        # ignored there, so they do not count as set here either.
        #
        # @return [Boolean]
        def any_set?
          ENV_MAPPING.any? do |key, env_var|
            !env_value(env_var, ENV_ALIASES[key]).nil?
          end
        end

        # Get configuration from environment
        # @return [Hash] configuration hash
        def configuration
          config = {}

          ENV_MAPPING.each do |key, env_var|
            value = env_value(env_var, ENV_ALIASES[key])
            next if value.nil?

            config[key] = parse_value(key, value)
          end

          config
        end

        private

        # Read an ENV variable, falling back to its alias
        # @param primary [String] primary variable name (without prefix)
        # @param fallback [String, nil] alias name (without prefix)
        # @return [String, nil] the value, or nil when unset/empty
        def env_value(primary, fallback)
          [primary, fallback].compact.each do |name|
            value = ENV.fetch("#{PREFIX}#{name}", nil)
            return value unless value.nil? || value.empty?
          end
          nil
        end

        # Parse value based on option type
        # @param key [Symbol] option key
        # @param value [String] raw value
        # @return [Object] parsed value
        def parse_value(key, value)
          case key
          when :sources
            value.split(',').map(&:strip).map(&:to_sym)
          when :connection_timeout, :read_timeout
            value.to_i
          when :verbose
            value.downcase == 'true'
          else
            value
          end
        end
      end
    end
  end
end
