# frozen_string_literal: true

require 'json'

module Ammitto
  module Cmd
    # Search command - search sanction entities
    #
    # Searches the data repository for matching entities.
    #
    # @example
    #   ammitto search "Kim Jong"                    # Search by name
    #   ammitto search "Putin" --type person         # Filter by entity type
    #   ammitto search "123 AVIATION" --source eu    # Filter by source
    #   ammitto search "ship" --type vessel          # Search vessels
    #
    class SearchCommand
      # Entity types that can be searched
      ENTITY_TYPES = %w[person organization vessel aircraft].freeze

      # @return [Hash] command options
      attr_reader :options

      # @return [String] search query
      attr_reader :query

      # Initialize with options and query
      # @param options [Hash] command options
      # @param query [String] search query
      def initialize(options, query)
        @options = options
        @query = query.to_s.strip
      end

      # Execute the command
      # @return [void]
      def run
        if query.empty?
          puts 'Error: Query required. Usage: ammitto search QUERY'
          puts '  ammitto search "Kim Jong"'
          puts '  ammitto search "ship" --type vessel'
          exit 1
        end

        if options[:format] == 'json'
          search_json
        else
          search_text
        end
      end

      private

      # Search and output as text
      # @return [void]
      def search_text
        results = perform_search

        if results.empty?
          puts "No results found for: #{query}"
          return
        end

        puts "Found #{results.length} result(s):"
        puts

        results.each_with_index do |result, idx|
          print_result(result, idx + 1)
        end
      end

      # Search and output as JSON
      # @return [void]
      def search_json
        results = perform_search
        puts JSON.pretty_generate(results.map(&:to_h))
      end

      # Perform the search
      # @return [Array<SearchResult>] search results
      def perform_search
        repo = create_repository

        unless repo.cloned?
          puts "Data repository not found. Run 'ammitto data clone' first."
          puts 'Or set AMMITTO_DATA_REPOSITORY environment variable.'
          return []
        end

        criteria = build_criteria
        entities = repo.query(criteria)

        entities.map do |entity|
          SearchResult.new(entity, entity['source'] || detect_source(entity['id']))
        end
      end

      # Create the data repository
      # @return [Ammitto::Data::Repository]
      def create_repository
        require_relative '../data/repository'
        local_path = options[:data_repository] || ENV.fetch('AMMITTO_DATA_REPOSITORY', nil)
        Ammitto::Data::Repository.new(
          local_path: local_path,
          verbose: options[:verbose]
        )
      end

      # Build query criteria from options
      # @return [Hash]
      def build_criteria
        criteria = { name: query }
        criteria[:source] = options[:source] if options[:source]
        criteria[:type] = options[:type] if options[:type]
        criteria[:limit] = options[:limit] || 50
        criteria
      end

      # Detect source from entity ID
      # @param id [String] entity ID
      # @return [String] source code
      def detect_source(id)
        return 'unknown' unless id

        # Extract source from ID like "https://www.ammitto.org/entity/eu/EU.123"
        match = id.match(%r{/entity/([^/]+)/})
        match ? match[1] : 'unknown'
      end

      # Print a single result
      # @param result [SearchResult]
      # @param index [Integer] result index
      # @return [void]
      def print_result(result, index)
        puts '=' * 60
        puts "##{index} #{result.primary_name}"
        puts '=' * 60
        puts JSON.pretty_generate(result.to_h)
        puts
      end

      # Search result wrapper
      class SearchResult
        # @return [Hash] entity data
        attr_reader :data

        # @return [String] source code
        attr_reader :source

        # Initialize with data and source
        # @param data [Hash] entity data
        # @param source [String] source code
        def initialize(data, source)
          @data = data
          @source = source
        end

        # Get entity ID
        # @return [String]
        def id
          data['id'] || data['@id'] || ''
        end

        # Get primary name
        # @return [String]
        def primary_name
          names = data['names'] || []
          primary = names.find { |n| n['is_primary'] } || names.first
          primary&.dig('full_name') || primary&.dig('fullName') || 'Unknown'
        end

        # Get entity type
        # @return [String]
        def entity_type
          data['entity_type'] || data['entityType'] || 'unknown'
        end

        # Get country
        # @return [String, nil]
        def country
          addresses = data['addresses'] || []
          addresses.first&.dig('country')
        end

        # Convert to hash - returns full entity data
        # @return [Hash]
        def to_h
          # Return the full entity data with source added
          data.merge('source' => source.to_s.upcase)
        end
      end
    end
  end
end
