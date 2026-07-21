# frozen_string_literal: true

require_relative 'defaults'
require_relative 'env_provider'

module Ammitto
  module Config
    # Override resolver for Ammitto configuration
    #
    # Implements three-tier configuration priority:
    #   1. ENV variables (highest priority)
    #   2. Programmatic API (Ammitto.configure)
    #   3. Defaults (lowest priority)
    #
    # @example Basic usage
    #   resolver = OverrideResolver.new
    #   resolver.resolve(:cache_dir) # => ENV > config > default
    #
    class OverrideResolver
      # @return [Hash] programmatic configuration
      attr_reader :config

      # Initialize with optional configuration
      # @param config [Hash] programmatic configuration
      def initialize(config = {})
        @config = config
      end

      # Resolve a configuration value
      # @param key [Symbol] configuration key
      # @param provided [Object, nil] directly provided value
      # @return [Object] resolved value
      def resolve(key, provided: nil)
        # 1. Use provided value if available
        return provided unless provided.nil?

        # 2. Check ENV variables
        env_value = env_config[key]
        return env_value unless env_value.nil?

        # 3. Check programmatic config
        config_value = @config[key]
        return config_value unless config_value.nil?

        # 4. Fall back to defaults
        default_value(key)
      end

      # Resolve all configuration values
      # @return [Hash] all resolved configuration
      def resolve_all
        {
          cache_dir: resolve(:cache_dir),
          api_base_url: resolve(:api_base_url),
          log_level: resolve(:log_level),
          sources: resolve(:sources),
          output_format: resolve(:output_format),
          connection_timeout: resolve(:connection_timeout),
          read_timeout: resolve(:read_timeout),
          verbose: resolve(:verbose)
        }
      end

      private

      # Get configuration from environment
      # @return [Hash]
      def env_config
        @env_config ||= EnvProvider.configuration
      end

      # Get default value for key
      # @param key [Symbol] configuration key
      # @return [Object] default value
      def default_value(key)
        case key
        when :cache_dir then Defaults::CACHE_DIR
        when :api_base_url then Defaults::API_BASE_URL
        when :log_level then Defaults::LOG_LEVEL
        when :sources then Defaults::DEFAULT_SOURCES
        when :output_format then Defaults::DEFAULT_OUTPUT_FORMAT
        when :connection_timeout then Defaults::CONNECTION_TIMEOUT
        when :read_timeout then Defaults::READ_TIMEOUT
        when :verbose then false
        end
      end
    end
  end
end
