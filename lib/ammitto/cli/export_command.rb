# frozen_string_literal: true

require 'fileutils'

module Ammitto
  module Cmd
    # Export command - export data to various formats
    #
    # Exports processed data to JSON-LD, Turtle, N-Triples, RDF/XML, or raw.
    class ExportCommand
      # @return [Hash] command options
      attr_reader :options

      # @return [String] export format
      attr_reader :format

      # Initialize with options and format
      # @param options [Hash] command options
      # @param format [String] export format
      def initialize(options, format)
        @options = options
        @format = normalize_format(format)
      end

      # Execute the command
      # @return [void]
      def run
        validate_format!

        if format == 'all'
          export_all_formats
        else
          export_single_format
        end
      end

      private

      # Normalize format string
      # @param format [String]
      # @return [String]
      def normalize_format(format)
        return 'all' if format.nil? || format.empty?

        format.downcase
      end

      # Validate format
      # @raise [ArgumentError] if invalid format
      def validate_format!
        valid = Config::Defaults::OUTPUT_FORMATS + ['all']

        return if valid.include?(format)

        raise ArgumentError,
              "Invalid format: #{format}. " \
              "Valid: #{valid.join(', ')}"
      end

      # Export all supported formats
      # @return [void]
      def export_all_formats
        Config::Defaults::OUTPUT_FORMATS.each do |fmt|
          @format = fmt
          export_single_format
        end
      end

      # Export single format
      # @return [void]
      def export_single_format
        output_dir = options[:output_dir] || './data'
        sources = parse_sources

        puts "Exporting #{format} to #{output_dir}..." if options[:verbose]

        # Ensure output directory exists
        FileUtils.mkdir_p(output_dir)

        if format == 'raw'
          export_raw(output_dir, sources)
        else
          export_rdf(output_dir, sources)
        end
      end

      # Parse sources from options
      # @return [Array<Symbol>]
      def parse_sources
        return Config::Defaults::ALL_SOURCES unless options[:sources]

        options[:sources].to_s.split(',').map do |s|
          s.strip.to_sym
        end
      end

      # Export in raw (source-specific) format
      # @param output_dir [String] output directory
      # @param sources [Array<Symbol>] sources to export
      # @return [void]
      def export_raw(output_dir, sources)
        processed_dir = File.join(cache_dir, 'processed')

        sources.each do |source|
          source_dir = File.join(processed_dir, source.to_s)
          next unless Dir.exist?(source_dir)

          output_source_dir = File.join(output_dir, 'sources', source.to_s)
          FileUtils.mkdir_p(output_source_dir)

          # Copy YAML files
          Dir.glob(File.join(source_dir, '*.yaml')).each do |file|
            FileUtils.cp(file, output_source_dir)
          end

          puts "[#{source}] Exported to #{output_source_dir}" if options[:verbose]
        end
      end

      # Export in RDF format
      # @param output_dir [String] output directory
      # @param sources [Array<Symbol>] sources to export
      # @return [void]
      def export_rdf(output_dir, sources)
        require_relative '../serialization/rdf_serializer'

        sources.each do |source|
          cache_file = File.join(cache_dir, 'cache', 'sources', source.to_s, "#{source}.jsonld")
          next unless File.exist?(cache_file)

          # Load entities from cache
          entities = load_entities_from_cache(cache_file)

          # Export to format
          serializer = Ammitto::Serialization::RdfSerializer.new(entities)
          output = serializer.serialize(format.to_sym)

          # Write output file
          ext = extension_for_format(format)
          output_file = File.join(output_dir, 'sources', "#{source}.#{ext}")
          FileUtils.mkdir_p(File.dirname(output_file))
          File.write(output_file, output)

          puts "[#{source}] Exported to #{output_file}" if options[:verbose]
        end

        # Export combined "all" file if multiple sources
        return unless sources.length > 1 && format != 'all'

        export_combined(output_dir, sources)
      end

      # Export combined file
      # @param output_dir [String] output directory
      # @param sources [Array<Symbol>] sources
      # @return [void]
      def export_combined(output_dir, sources)
        all_entities = []

        sources.each do |source|
          cache_file = File.join(cache_dir, 'cache', 'sources', source.to_s, "#{source}.jsonld")
          next unless File.exist?(cache_file)

          all_entities.concat(load_entities_from_cache(cache_file))
        end

        return if all_entities.empty?

        ext = extension_for_format(format)
        output_file = File.join(output_dir, "all.#{ext}")

        serializer = Ammitto::Serialization::RdfSerializer.new(all_entities)
        File.write(output_file, serializer.serialize(format.to_sym))

        puts "[all] Exported to #{output_file}" if options[:verbose]
      end

      # Load entities from JSON-LD cache file
      # @param file [String] file path
      # @return [Array<Hash>]
      def load_entities_from_cache(file)
        require 'json'

        data = JSON.parse(File.read(file))
        graph = data['@graph'] || []

        graph.select do |item|
          type = item['@type']
          type.is_a?(String) && type.include?('Entity')
        end
      rescue StandardError
        []
      end

      # Get file extension for format
      # @param fmt [String] format
      # @return [String] extension
      def extension_for_format(fmt)
        case fmt
        when 'jsonld' then 'jsonld'
        when 'ttl' then 'ttl'
        when 'nt' then 'nt'
        when 'rdfxml' then 'rdf'
        else 'txt'
        end
      end

      # Get cache directory
      # @return [String]
      def cache_dir
        options[:cache_dir] || File.expand_path('~/.ammitto')
      end
    end
  end
end
