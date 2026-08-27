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
        @skipped_sources = []
      end

      # Build the query (returns self for chaining)
      # @return [QueryBuilder] self
      def build
        self
      end

      # Sources this query could not read, populated by #execute.
      #
      # A search that quietly returns fewer results than the corpus holds
      # is the dangerous direction for a sanctions dataset: the caller
      # sees no match and cannot tell that from "three sources did not
      # load". The skip itself is correct — one unreachable source must
      # not take the whole search down — but it has to be reportable.
      #
      # @return [Array<Symbol>] source codes skipped by the last #execute
      attr_reader :skipped_sources

      # Execute the search
      # @return [Array<Hash>] matching results
      def execute
        @skipped_sources = []
        return [] if term.empty?

        results = []

        sources.each do |code|
          source = Registry.instance(code)
          unless source
            # The registry is mutable and #instance may return nil. A code
            # we cannot instantiate is a source we did not read, and the
            # whole point of this list is that unread is not the same as
            # empty — so record it rather than dropping it silently.
            Logger.warn("Search skipping #{code}: no registered source")
            @skipped_sources << code
            next
          end

          # The registry knows every source the gem has ever shipped;
          # the published API only carries the currently built ones.
          # A source whose download fails must not take the whole
          # search down with it, or the default all-sources call
          # raises before reading a single published row.
          begin
            data = source.load_data
          rescue NetworkError => e
            Logger.warn("Search skipping #{code}: #{e.message}")
            @skipped_sources << code
            next
          end

          matches = source.search(term, data)
          results.concat(matches)
        end

        # Apply pagination (offset applies with or without a limit;
        # past-the-end pages return [] rather than nil)
        results = results.drop(offset) if offset.positive?
        results = results.take(limit) if limit

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
