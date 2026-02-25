# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'

module Ammitto
  module Data
    # Repository manages the local clone of the Ammitto data repository
    #
    # The data repository contains harmonized JSON-LD data for all sources.
    # It can be configured via AMMITTO_DATA_REPOSITORY environment variable.
    #
    # Supports both local paths and git URLs:
    # - Local path: /path/to/data or ./data
    # - Git URL: https://github.com/ammitto/data.git or git@github.com:ammitto/data.git
    #
    # @example Clone the data repository
    #   repo = Ammitto::Data::Repository.new
    #   repo.clone
    #
    # @example Use a git URL
    #   repo = Ammitto::Data::Repository.new(local_path: 'https://github.com/ammitto/data.git')
    #   repo.ensure_available  # Auto-clones to ~/.ammitto/data
    #
    # @example Query entities
    #   entities = repo.query(name: "Smith")
    #
    class Repository
      # Default remote URL for the data repository
      DEFAULT_REMOTE_URL = 'https://github.com/ammitto/data.git'

      # Default local cache directory
      DEFAULT_LOCAL_PATH = File.expand_path('~/.ammitto/data')

      # URL patterns for detecting git URLs
      URL_PATTERN = /\A(?:https?|git):\/\/|git@/

      # @return [String] Local path for the repository
      attr_reader :local_path

      # @return [String] Remote URL for the repository
      attr_reader :remote_url

      # @return [Boolean] Whether to enable verbose output
      attr_reader :verbose

      # Initialize a new Repository
      #
      # @param local_path [String] Local path or git URL for the repository
      # @param remote_url [String] Remote URL for the repository (optional)
      # @param verbose [Boolean] Enable verbose output
      def initialize(local_path: nil, remote_url: nil, verbose: false)
        @verbose = verbose

        # Parse local_path - it might be a URL
        path = local_path || default_path_from_env
        if url?(path)
          @remote_url = path
          @local_path = DEFAULT_LOCAL_PATH
        else
          @local_path = path || DEFAULT_LOCAL_PATH
          @remote_url = remote_url || DEFAULT_REMOTE_URL
        end
      end

      # Check if the repository is cloned
      #
      # @return [Boolean]
      def cloned?
        File.directory?(File.join(local_path, '.git')) ||
          File.exist?(File.join(local_path, 'api', 'v1', 'stats.json'))
      end

      # Clone the data repository
      #
      # @param force [Boolean] Force re-clone if already exists
      # @return [Boolean] true if clone succeeded
      def clone(force: false)
        if cloned? && !force
          log("Repository already available at #{local_path}")
          return true
        end

        if force && File.directory?(local_path)
          log("Removing existing repository at #{local_path}")
          FileUtils.rm_rf(local_path)
        end

        FileUtils.mkdir_p(File.dirname(local_path))

        log("Cloning #{remote_url} to #{local_path}")
        success, output = run_git_command('clone', '--depth', '1', remote_url, local_path)

        unless success
          raise Ammitto::Error, "Failed to clone repository: #{output}"
        end

        log("Clone complete")
        true
      end

      # Pull latest changes from remote
      #
      # @return [Boolean] true if pull succeeded
      def pull
        unless File.directory?(File.join(local_path, '.git'))
          raise Ammitto::Error, "Repository not a git repository. Cannot pull."
        end

        log("Pulling updates from #{remote_url}")
        success, output = run_git_command('-C', local_path, 'pull', '--ff-only')

        unless success
          raise Ammitto::Error, "Failed to pull updates: #{output}"
        end

        log("Pull complete")
        true
      end

      # Get the path to the API data directory
      #
      # @return [String]
      def api_path
        File.join(local_path, 'api', 'v1')
      end

      # Get the path to the sources directory
      #
      # @return [String]
      def sources_path
        File.join(api_path, 'sources')
      end

      # Get list of available sources
      #
      # @return [Array<String>]
      def sources
        return [] unless File.directory?(sources_path)

        Dir.glob('*.jsonld', base: sources_path).map { |f| File.basename(f, '.jsonld') }
      end

      # Get statistics about the data
      #
      # @return [Hash]
      def stats
        stats_file = File.join(api_path, 'stats.json')
        return {} unless File.exist?(stats_file)

        JSON.parse(File.read(stats_file))
      end

      # Load all entities from a source
      #
      # @param source [String] Source code (e.g., 'eu', 'un', 'us')
      # @return [Array<Hash>] Array of entities
      def load_source(source)
        source_file = File.join(sources_path, "#{source}.jsonld")
        raise Ammitto::NotFoundError, "Source not found: #{source}" unless File.exist?(source_file)

        data = JSON.parse(File.read(source_file))
        data['@graph'] || []
      end

      # Load all entities from all sources
      #
      # @return [Array<Hash>] Array of all entities
      def load_all
        all_file = File.join(api_path, 'all.jsonld')
        raise Ammitto::NotFoundError, "Combined data not found" unless File.exist?(all_file)

        data = JSON.parse(File.read(all_file))
        data['@graph'] || []
      end

      # Query entities by criteria
      #
      # @param criteria [Hash] Query criteria
      # @option criteria [String] :name Name to search for (partial match)
      # @option criteria [String] :source Source code to filter by
      # @option criteria [String] :type Entity type to filter by
      # @option criteria [String] :country Country to filter by
      # @option criteria [Integer] :limit Maximum number of results
      # @option criteria [Integer] :offset Offset for pagination
      # @return [Array<Hash>] Matching entities
      def query(criteria = {})
        entities = if criteria[:source]
                     load_source(criteria[:source])
                   else
                     load_all
                   end

        # Filter by name
        if criteria[:name]
          name_lower = criteria[:name].downcase
          entities = entities.select do |e|
            names = e['names'] || []
            names.any? do |n|
              n['full_name']&.downcase&.include?(name_lower)
            end
          end
        end

        # Filter by type
        if criteria[:type]
          type_lower = criteria[:type].downcase
          entities = entities.select do |e|
            e['entity_type']&.downcase == type_lower
          end
        end

        # Filter by country
        if criteria[:country]
          country_lower = criteria[:country].downcase
          entities = entities.select do |e|
            addresses = e['addresses'] || []
            addresses.any? { |a| a['country']&.downcase&.include?(country_lower) }
          end
        end

        # Apply pagination
        offset = criteria[:offset] || 0
        limit = criteria[:limit]

        entities = entities.drop(offset)
        entities = entities.take(limit) if limit

        entities
      end

      # Get an entity by ID
      #
      # @param id [String] Entity ID
      # @return [Hash, nil] Entity data or nil if not found
      def get(id)
        entities = load_all
        entities.find { |e| e['id'] == id }
      end

      # Ensure the repository is cloned and up to date
      #
      # @param pull [Boolean] Whether to pull updates
      # @return [Boolean]
      def ensure_available(pull: false)
        return true if cloned?

        clone
        self.pull if pull
        true
      end

      private

      # Get default path from environment variable
      #
      # @return [String, nil]
      def default_path_from_env
        env_path = ENV['AMMITTO_DATA_REPOSITORY']
        return nil if env_path.nil? || env_path.empty?

        env_path
      end

      # Check if a path is a URL
      #
      # @param path [String] Path to check
      # @return [Boolean]
      def url?(path)
        path.to_s.match?(URL_PATTERN)
      end

      # Run a git command
      #
      # @param args [Array<String>] Git arguments
      # @return [Array<Boolean, String>] Success status and output
      def run_git_command(*args)
        cmd = ['git'] + args
        log("Running: #{cmd.join(' ')}")

        output, status = Open3.capture2e(*cmd)
        [status.success?, output]
      end

      # Log a message if verbose mode is enabled
      #
      # @param message [String] Message to log
      def log(message)
        puts "[ammitto] #{message}" if verbose
      end
    end
  end
end
