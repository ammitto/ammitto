# frozen_string_literal: true

require 'json'

module Ammitto
  module Cmd
    # Search command - search cached data
    #
    # Searches cached sanction data for matching entities.
    class SearchCommand
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
        sources = parse_sources
        results = []

        sources.each do |source|
          source_results = search_source(source)
          results.concat(source_results)
        end

        # Limit results
        limit = options[:limit] || 50
        results.first(limit)
      end

      # Parse sources from options
      # @return [Array<Symbol>]
      def parse_sources
        return Config::Defaults::ALL_SOURCES unless options[:sources]

        options[:sources].to_s.split(',').map do |s|
          s.strip.to_sym
        end
      end

      # Search a single source
      # @param source [Symbol] source code
      # @return [Array<SearchResult>]
      def search_source(source)
        cache_file = File.join(cache_dir, 'cache', 'sources', source.to_s, "#{source}.jsonld")
        return [] unless File.exist?(cache_file)

        require 'json'
        data = JSON.parse(File.read(cache_file))
        graph = data['@graph'] || []

        # Find matching entities
        graph.select do |item|
          next unless item['@type']&.include?('Entity')

          matches_query?(item)
        end.map { |item| SearchResult.new(item, source) }
      rescue StandardError
        []
      end

      # Check if entity matches query
      # @param entity [Hash] entity data
      # @return [Boolean]
      def matches_query?(entity)
        query_lower = query.downcase

        # Search in names
        names = entity['names'] || []
        return true if names.any? { |n| n['fullName']&.downcase&.include?(query_lower) }

        # Search in reference number
        ref = entity['sourceReferences'] || []
        return true if ref.any? { |r| r['referenceNumber']&.downcase&.include?(query_lower) }

        # Search in ID
        return true if entity['@id']&.downcase&.include?(query_lower)

        false
      end

      # Print a single result
      # @param result [SearchResult]
      # @param index [Integer] result index
      # @return [void]
      def print_result(result, index)
        puts "#{index}. #{result.primary_name}"
        puts "   Source: #{result.source.upcase}"
        puts "   Type: #{result.entity_type}"
        puts "   ID: #{result.id}"
        puts
      end

      # Get cache directory
      # @return [String]
      def cache_dir
        options[:cache_dir] || File.expand_path('~/.ammitto')
      end

      # Search result wrapper
      class SearchResult
        # @return [Hash] entity data
        attr_reader :data

        # @return [Symbol] source code
        attr_reader :source

        # Initialize with data and source
        # @param data [Hash] entity data
        # @param source [Symbol] source code
        def initialize(data, source)
          @data = data
          @source = source
        end

        # Get entity ID
        # @return [String]
        def id
          data['@id'] || ''
        end

        # Get primary name
        # @return [String]
        def primary_name
          names = data['names'] || []
          primary = names.find { |n| n['isPrimary'] } || names.first
          primary&.dig('fullName') || 'Unknown'
        end

        # Get entity type
        # @return [String]
        def entity_type
          data['entityType'] || 'unknown'
        end

        # Convert to hash
        # @return [Hash]
        def to_h
          {
            id: id,
            name: primary_name,
            type: entity_type,
            source: source.to_s.upcase
          }
        end
      end
    end
  end
end
