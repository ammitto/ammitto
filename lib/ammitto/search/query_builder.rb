# frozen_string_literal: true

module Ammitto
  module Search
    # QueryBuilder builds and executes search queries
    #
    # @example Basic search
    #   query = QueryBuilder.new("Kim Jong", sources: [:un, :us])
    #   results = query.build.execute
    #
    class QueryBuilder
      # @return [String] the search term
      attr_reader :term

      # @return [Array<Symbol>] sources to search
      attr_reader :sources

      # @return [Integer] maximum results
      attr_reader :limit

      # @return [Integer] offset for pagination
      attr_reader :offset

      # Initialize the query builder
      # @param term [String] the search term
      # @param options [Hash] search options
      # @option options [Array<Symbol>] :sources sources to search
      # @option options [Integer] :limit maximum results
      # @option options [Integer] :offset offset for pagination
      def initialize(term, options = {})
        @term = term.to_s.strip
        @sources = normalize_sources(options[:sources])
        @limit = options[:limit]
        @offset = options[:offset] || 0
      end

      # Build the query (returns self for chaining)
      # @return [QueryBuilder] self
      def build
        self
      end

      # Execute the search
      # @return [Array<Hash>] matching results
      def execute
        return [] if term.empty?

        results = []

        sources.each do |code|
          source = Registry.instance(code)
          next unless source

          data = source.load_data
          matches = source.search(term, data)
          results.concat(matches)
        end

        # Apply pagination
        results = results.slice(offset, limit) if limit

        results
      end

      private

      # Normalize sources parameter
      # @param sources [Array<Symbol>, Symbol, nil] the sources
      # @return [Array<Symbol>] normalized sources
      def normalize_sources(sources)
        return Registry.codes if sources.nil?

        Array(sources).map(&:to_sym).select { |s| Registry.registered?(s) }
      end
    end
  end
end
