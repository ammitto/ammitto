# frozen_string_literal: true

require 'fileutils'

module Ammitto
  module Cmd
    # Process command - process raw data into harmonized models
    #
    # Processes downloaded raw data into harmonized Ammitto entities.
    class ProcessCommand
      # @return [Hash] command options
      attr_reader :options

      # @return [Array<Symbol>] sources to process
      attr_reader :sources

      # Initialize with options and sources
      # @param options [Hash] command options
      # @param sources [Array<String>] source codes
      def initialize(options, sources)
        @options = options
        @sources = normalize_sources(sources)
      end

      # Execute the command
      # @return [void]
      def run
        validate_sources!

        if @sources.empty?
          puts "No sources to process. Run 'ammitto fetch' first."
          return
        end

        process_all
      end

      private

      # Normalize source codes
      # @param sources [Array<String>]
      # @return [Array<Symbol>]
      def normalize_sources(sources)
        if sources.empty?
          # Process sources that have raw data
          find_sources_with_raw_data
        else
          sources.map(&:to_s).map(&:downcase).map(&:to_sym)
        end
      end

      # Find sources with raw data
      # @return [Array<Symbol>]
      def find_sources_with_raw_data
        raw_dir = File.join(cache_dir, 'raw')

        return [] unless Dir.exist?(raw_dir)

        Dir.children(raw_dir).select do |child|
          path = File.join(raw_dir, child)
          Dir.exist?(path) && !Dir.empty?(path)
        end.map(&:to_sym)
      end

      # Validate source codes
      # @raise [ArgumentError] if invalid source
      def validate_sources!
        invalid = @sources - Config::Defaults::ALL_SOURCES
        return if invalid.empty?

        raise ArgumentError,
              "Invalid sources: #{invalid.join(', ')}. " \
              "Valid: #{Config::Defaults::ALL_SOURCES.join(', ')}"
      end

      # Process all sources
      # @return [void]
      def process_all
        results = @sources.map do |source|
          process_source(source)
        end

        print_summary(results)
      end

      # Process a single source
      # @param source [Symbol] source code
      # @return [Hash] process result
      def process_source(source)
        puts "[#{source}] Processing..." if options[:verbose]

        # Load pipeline
        require_relative '../pipeline'

        pipeline = Ammitto::Pipeline.new(
          source: source,
          cache_dir: cache_dir,
          verbose: options[:verbose]
        )

        result = pipeline.run
        result.merge(code: source)
      rescue StandardError => e
        puts "[#{source}] ERROR: #{e.message}" if options[:verbose]
        { code: source, status: :error, error: e.message }
      end

      # Get cache directory
      # @return [String]
      def cache_dir
        options[:cache_dir] || File.expand_path('~/.ammitto')
      end

      # Print summary of results
      # @param results [Array<Hash>] process results
      # @return [void]
      def print_summary(results)
        success = results.count { |r| r[:status] == :success }
        failed = results.count { |r| r[:status] == :error }

        puts
        puts "Process complete: #{success} succeeded, #{failed} failed"

        return unless failed.positive?

        puts 'Failed sources:'
        results.select { |r| r[:status] == :error }.each do |r|
          puts "  #{r[:code]}: #{r[:error]}"
        end
      end
    end
  end
end
