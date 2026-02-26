# frozen_string_literal: true

require_relative '../config/defaults'

module Ammitto
  module Options
    # Registry for all CLI and API options
    #
    # Single source of truth for option definitions, types, defaults,
    # environment variable mappings, and CLI flags.
    #
    # @example Getting an option definition
    #   Options::Registry[:cache_dir]
    #   # => { type: :string, default: "~/.ammitto", env: "AMMITTO_CACHE_DIR", ... }
    #
    # @example Resolving an option value
    #   Options::Registry.resolve(:cache_dir, provided: "/tmp/cache")
    #   # => "/tmp/cache"
    #
    class Registry
      # All option definitions
      OPTIONS = {
        cache_dir: {
          type: :string,
          default: Config::Defaults::CACHE_DIR,
          env: 'AMMITTO_CACHE_DIR',
          desc: 'Directory for caching data',
          cli_flag: '--cache-dir DIR',
          cli_short: '-c DIR'
        },

        api_base_url: {
          type: :string,
          default: Config::Defaults::API_BASE_URL,
          env: 'AMMITTO_API_BASE_URL',
          desc: 'Base URL for Ammitto API',
          cli_flag: '--api-url URL',
          cli_short: '-u URL'
        },

        sources: {
          type: :array,
          default: Config::Defaults::DEFAULT_SOURCES,
          env: 'AMMITTO_SOURCES',
          desc: 'Sanction sources to process',
          cli_flag: '--sources SOURCE1,SOURCE2',
          cli_short: '-s SOURCES',
          allowed: Config::Defaults::ALL_SOURCES.map(&:to_s)
        },

        sources_dir: {
          type: :string,
          default: Config::Defaults::SOURCES_DIR,
          env: 'AMMITTO_SOURCES_DIR',
          desc: 'Directory containing data-* repositories',
          cli_flag: '--sources-dir DIR'
        },

        scan: {
          type: :boolean,
          default: false,
          desc: 'Auto-detect data-* repositories',
          cli_flag: '--scan'
        },

        output_format: {
          type: :string,
          default: Config::Defaults::DEFAULT_OUTPUT_FORMAT,
          env: 'AMMITTO_OUTPUT_FORMAT',
          desc: 'Output format',
          cli_flag: '--format FORMAT',
          cli_short: '-f FORMAT',
          allowed: Config::Defaults::OUTPUT_FORMATS
        },

        output_dir: {
          type: :string,
          default: './data',
          env: 'AMMITTO_OUTPUT_DIR',
          desc: 'Output directory for exports',
          cli_flag: '--output-dir DIR',
          cli_short: '-o DIR'
        },

        log_level: {
          type: :string,
          default: Config::Defaults::LOG_LEVEL,
          env: 'AMMITTO_LOG_LEVEL',
          desc: 'Log level (debug, info, warn, error)',
          cli_flag: '--log-level LEVEL',
          allowed: %w[debug info warn error]
        },

        verbose: {
          type: :boolean,
          default: false,
          env: 'AMMITTO_VERBOSE',
          desc: 'Enable verbose output',
          cli_flag: '--verbose',
          cli_short: '-v'
        },

        force: {
          type: :boolean,
          default: false,
          desc: 'Force operation, ignoring cache',
          cli_flag: '--force'
        },

        dry_run: {
          type: :boolean,
          default: false,
          desc: 'Show what would be done without making changes',
          cli_flag: '--dry-run'
        },

        connection_timeout: {
          type: :integer,
          default: Config::Defaults::CONNECTION_TIMEOUT,
          env: 'AMMITTO_CONNECTION_TIMEOUT',
          desc: 'HTTP connection timeout in seconds',
          cli_flag: '--connection-timeout SECONDS'
        },

        read_timeout: {
          type: :integer,
          default: Config::Defaults::READ_TIMEOUT,
          env: 'AMMITTO_READ_TIMEOUT',
          desc: 'HTTP read timeout in seconds',
          cli_flag: '--read-timeout SECONDS'
        },

        limit: {
          type: :integer,
          default: nil,
          desc: 'Limit number of results',
          cli_flag: '--limit N'
        },

        query: {
          type: :string,
          default: nil,
          desc: 'Search query',
          cli_flag: '--query QUERY'
        }
      }.freeze

      class << self
        # Get all option names
        # @return [Array<Symbol>]
        def option_names
          OPTIONS.keys
        end

        # Get option definition
        # @param name [Symbol] option name
        # @return [Hash, nil] option definition
        def [](name)
          OPTIONS[name]
        end

        # Check if option exists
        # @param name [Symbol] option name
        # @return [Boolean]
        def exists?(name)
          OPTIONS.key?(name)
        end

        # Get default value for option
        # @param name [Symbol] option name
        # @return [Object] default value
        def default(name)
          option = OPTIONS[name]
          option&.fetch(:default, nil)
        end

        # Get option type
        # @param name [Symbol] option name
        # @return [Symbol] type (:string, :integer, :boolean, :array)
        def type(name)
          option = OPTIONS[name]
          option&.fetch(:type, :string)
        end

        # Get allowed values for option
        # @param name [Symbol] option name
        # @return [Array, nil] allowed values
        def allowed(name)
          option = OPTIONS[name]
          option&.fetch(:allowed, nil)
        end

        # Resolve option value with priority chain
        # @param name [Symbol] option name
        # @param provided [Object, nil] directly provided value
        # @return [Object] resolved value
        def resolve(name, provided: nil)
          return provided unless provided.nil?

          # Check ENV
          option = OPTIONS[name]
          if option && option[:env]
            env_value = ENV[option[:env]]
            return parse_value(name, env_value) if env_value && !env_value.empty?
          end

          # Fall back to default
          option&.fetch(:default, nil)
        end

        # Parse value based on option type
        # @param name [Symbol] option name
        # @param value [String] raw value
        # @return [Object] parsed value
        def parse_value(name, value)
          return nil if value.nil?

          case type(name)
          when :integer
            value.to_i
          when :boolean
            %w[true yes 1].include?(value.to_s.downcase)
          when :array
            value.to_s.split(',').map(&:strip)
          else
            value
          end
        end

        # Register Thor options for a command
        # @param thor_class [Class] Thor class
        # @param option_keys [Array<Symbol>] options to register
        def register_thor_options(thor_class, option_keys)
          option_keys.each do |key|
            option = OPTIONS[key]
            next unless option

            thor_class.class_option key,
                                    type: option[:type],
                                    default: option[:default],
                                    desc: option[:desc],
                                    aliases: option[:cli_short] ? [option[:cli_short]] : []
          end
        end
      end
    end
  end
end
