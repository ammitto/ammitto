# frozen_string_literal: true

require 'json'
require 'fileutils'

module Ammitto
  module Cmd
    # Status command - show cache and data status
    #
    # Displays current cache status for all sources.
    class StatusCommand
      # @return [Hash] command options
      attr_reader :options

      # Initialize with options
      # @param options [Hash] command options
      def initialize(options)
        @options = options
      end

      # Execute the command
      # @return [void]
      def run
        if options[:format] == 'json'
          output_json
        else
          output_table
        end
      end

      private

      # Get cache directory from options or default
      # @return [String]
      def cache_dir
        options[:cache_dir] || File.expand_path('~/.ammitto')
      end

      # Get status data for all sources
      # @return [Array<Hash>]
      def status_data
        Config::Defaults::ALL_SOURCES.map do |source|
          source_status(source)
        end
      end

      # Get status for a single source
      # @param source [Symbol] source code
      # @return [Hash] source status
      def source_status(source)
        source_dir = File.join(cache_dir, 'cache', 'sources', source.to_s)
        jsonld_file = File.join(source_dir, "#{source}.jsonld")
        metadata_file = File.join(source_dir, 'metadata.json')

        if File.exist?(jsonld_file)
          stat = File.stat(jsonld_file)
          {
            code: source.to_s,
            status: 'cached',
            entities: count_entities(jsonld_file),
            last_updated: stat.mtime.strftime('%Y-%m-%d')
          }
        elsif File.exist?(metadata_file)
          metadata = JSON.parse(File.read(metadata_file))
          {
            code: source.to_s,
            status: 'stale',
            entities: metadata['entities'] || 0,
            last_updated: metadata['last_updated'] || 'unknown'
          }
        else
          {
            code: source.to_s,
            status: 'not fetched',
            entities: 0,
            last_updated: 'never'
          }
        end
      rescue StandardError => e
        {
          code: source.to_s,
          status: 'error',
          entities: 0,
          last_updated: "error: #{e.message}"
        }
      end

      # Count entities in JSON-LD file
      # @param file [String] file path
      # @return [Integer] entity count
      def count_entities(file)
        content = File.read(file)
        data = JSON.parse(content)

        graph = data['@graph'] || data
        return 0 unless graph.is_a?(Array)

        graph.count { |item| item['@type']&.include?('Entity') }
      rescue StandardError
        0
      end

      # Output as table
      # @return [void]
      def output_table
        puts 'Cache Status:'
        puts
        puts format_row('Source', 'Status', 'Entities', 'Last Updated')
        puts '-' * 60

        status_data.each do |status|
          puts format_row(
            status[:code].upcase,
            status[:status],
            status[:entities].to_s,
            status[:last_updated]
          )
        end

        puts
        puts "Run 'ammitto fetch' to download latest data."
      end

      # Output as JSON
      # @return [void]
      def output_json
        puts JSON.pretty_generate(status_data)
      end

      # Format a table row
      # @return [String]
      def format_row(code, status, entities, updated)
        format('%-8s %-15s %-10s %s', code, status, entities, updated)
      end
    end
  end
end
