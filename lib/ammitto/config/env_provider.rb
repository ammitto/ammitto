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
        verbose: 'VERBOSE'
      }.freeze

      class << self
        # Check if any Ammitto ENV variables are set
        # @return [Boolean]
        def any_set?
          ENV_MAPPING.keys.any? { |key| ENV["#{PREFIX}#{key}"] }
        end

        # Get configuration from environment
        # @return [Hash] configuration hash
        def configuration
          config = {}

          ENV_MAPPING.each do |key, env_var|
            value = ENV["#{PREFIX}#{env_var}"]
            next if value.nil? || value.empty?

            config[key] = parse_value(key, value)
          end

          config
        end

        private

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
