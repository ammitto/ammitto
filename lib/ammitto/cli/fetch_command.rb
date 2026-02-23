# frozen_string_literal: true

require 'fileutils'
require_relative '../config/defaults'

module Ammitto
  module Cmd
    # Fetch command - download raw data from sources
    #
    # Downloads sanction data from specified sources and saves to YAML or JSON-LD.
    #
    # @example Fetch UK data as YAML
    #   ammitto fetch uk --format yaml --output-dir ./processed
    #
    # @example Fetch all sources
    #   ammitto fetch --all
    #
    class FetchCommand
      # @return [Hash] command options
      attr_reader :options

      # @return [Array<Symbol>] sources to fetch
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

        if options[:dry_run]
          dry_run
        else
          fetch_all
        end
      end

      private

      # Normalize source codes to symbols
      # @param sources [Array<String>]
      # @return [Array<Symbol>]
      def normalize_sources(sources)
        if sources.empty? || options[:all]
          Config::Defaults::ALL_SOURCES
        else
          sources.map(&:to_s).map(&:downcase).map(&:to_sym)
        end
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

      # Show what would be done (dry run)
      # @return [void]
      def dry_run
        puts 'Would fetch data from:'
        @sources.each do |source|
          extractor_class = extractor_class_for(source)
          endpoint = extractor_class&.new&.api_endpoint
          puts "  #{source}: #{endpoint || 'N/A'}"
        end
      end

      # Fetch all sources
      # @return [void]
      def fetch_all
        results = []

        @sources.each do |source|
          results << fetch_source(source)
        end

        print_summary(results)
      end

      # Fetch a single source
      # @param source [Symbol] source code
      # @return [Hash] fetch result
      def fetch_source(source)
        puts "[#{source}] Fetching..." if options[:verbose]

        extractor_class = extractor_class_for(source)
        return error_result(source, 'No extractor available') unless extractor_class

        # Create output directory
        output_dir = options[:output_dir] || File.join(cache_dir, 'processed', source.to_s)
        FileUtils.mkdir_p(output_dir)

        # Create extractor instance
        extractor = extractor_class.new
        extractor.verbose = options[:verbose] if extractor.respond_to?(:verbose=)

        # Fetch and parse using source models if format is yaml
        format = options[:format] || 'yaml'

        if format == 'yaml' && source_model_class_for(source)
          fetch_with_source_models(source, extractor, output_dir)
        else
          extractor.run
        end
      rescue StandardError => e
        puts "[#{source}] ERROR: #{e.message}" if options[:verbose]
        puts e.backtrace.first(5).join("\n") if options[:verbose]
        error_result(source, e.message)
      end

      # Fetch data using Lutaml::Model source models
      # @param source [Symbol] source code
      # @param extractor [BaseExtractor] the extractor
      # @param output_dir [String] output directory
      # @return [Hash] fetch result
      def fetch_with_source_models(source, extractor, output_dir)
        puts "[#{source}] Fetching with source models..." if options[:verbose]

        # Fetch raw content using extractor's fetch method (handles tokens, etc.)
        puts "[#{source}] Downloading from #{extractor.api_endpoint}" if options[:verbose]
        content = extractor.fetch

        # Parse using source model
        model_class = source_model_class_for(source)
        raise "No source model for #{source}" unless model_class

        puts "[#{source}] Parsing with #{model_class.name}..." if options[:verbose]

        # Detect format and parse accordingly
        data = case source
               when :wb
                 require 'json'
                 # WB model's from_json expects the raw JSON string
                 model_class.from_json(content)
               when :au, :tr, :nz, :eu_vessels
                 # AU, TR, NZ, EU Vessels use XLSX - content is path to temp file
                 result = model_class.from_xlsx(content)
                 extractor.cleanup if extractor.respond_to?(:cleanup)
                 result
               when :jp, :un_vessels
                 # JP, UN Vessels are PDF-based - requires manual conversion
                 puts "[#{source}] Note: #{source.upcase} data is PDF-based"
                 puts "[#{source}] Data requires manual conversion from PDF"
                 model_class.from_pdf(content)
               else
                 model_class.from_xml(content)
               end

        # Save as individual YAML files
        count = save_as_yaml(source, data, output_dir)

        {
          code: source,
          status: :success,
          count: count,
          output_dir: output_dir
        }
      end

      # Save data as individual YAML files
      # @param source [Symbol] source code
      # @param data [Object] the parsed data
      # @param output_dir [String] output directory
      # @return [Integer] number of files saved
      def save_as_yaml(source, data, output_dir)
        count = 0

        # Get the collection of designations/entities
        items = items_from_data(source, data)

        items.each do |item|
          # Generate filename from unique ID
          filename = filename_for_item(source, item)
          filepath = File.join(output_dir, filename)

          # Write YAML
          yaml_content = item.to_yaml
          File.write(filepath, yaml_content)
          count += 1

          puts "[#{source}] Saved #{count} files..." if options[:verbose] && (count % 100).zero?
        end

        # Save index file with metadata
        index = {
          'source' => source.to_s,
          'count' => count,
          'fetched_at' => Time.now.utc.iso8601,
          'schema' => "ammitto:sources:#{source}:v1"
        }
        File.write(File.join(output_dir, '_index.yaml'), index.to_yaml)

        puts "[#{source}] Saved #{count} files to #{output_dir}" if options[:verbose]

        count
      end

      # Get items collection from parsed data
      # @param source [Symbol] source code
      # @param data [Object] parsed data
      # @return [Array] collection of items
      def items_from_data(source, data)
        case source
        when :uk
          data.designations || []
        when :eu
          data.sanction_entities || []
        when :un
          (data.all_individuals || []) + (data.all_entities || [])
        when :us
          data.entries || []
        when :wb
          data.firms || []
        when :au
          (data.individuals || []) + (data.organizations || []) + (data.vessels || [])
        when :ca
          (data.individuals || []) + (data.entities || [])
        when :ch
          (data.individuals || []) + (data.entities || [])
        when :cn
          data.entities || []
        when :ru
          data.entities || []
        when :tr
          data.entities || []
        when :nz
          (data.individuals || []) + (data.entities || []) + (data.ships || [])
        when :eu_vessels
          data.vessels || []
        when :jp
          data.entities || []
        when :un_vessels
          data.vessels || []
        else
          []
        end
      end

      # Generate filename for an item
      # @param source [Symbol] source code
      # @param item [Object] the item
      # @return [String] filename
      def filename_for_item(source, item)
        case source
        when :uk
          ref = item.unique_id || "unknown-#{item.object_id}"
          "#{ref.downcase.gsub(/[^a-z0-9]/, '-')}.yaml"
        when :eu
          ref = item.eu_reference_number || "unknown-#{item.object_id}"
          "#{ref.downcase.gsub(/[^a-z0-9]/, '-')}.yaml"
        when :un
          ref = item.reference_number || "unknown-#{item.object_id}"
          "#{ref.downcase.gsub(/[^a-z0-9]/, '-')}.yaml"
        when :us
          ref = item.uid || "unknown-#{item.object_id}"
          "#{ref.downcase.gsub(/[^a-z0-9]/, '-')}.yaml"
        when :wb
          ref = item.supp_id || "unknown-#{item.object_id}"
          "wb-#{ref}.yaml"
        when :au
          ref = item.reference || item.id || "unknown-#{item.object_id}"
          "au-#{ref}.yaml"
        when :ca
          ref = item.id || "unknown-#{item.object_id}"
          "ca-#{ref}.yaml"
        when :ch
          ref = item.id || "unknown-#{item.object_id}"
          "ch-#{ref}.yaml"
        when :cn
          ref = item.id || item.chinese_name || "unknown-#{item.object_id}"
          "#{ref.to_s.downcase.gsub(/[^a-z0-9]/, '-')}.yaml"
        when :ru
          ref = item.id || item.russian_name || "unknown-#{item.object_id}"
          "#{ref.to_s.downcase.gsub(/[^a-z0-9]/, '-')}.yaml"
        when :tr
          ref = item.reference_number || item.name || "unknown-#{item.object_id}"
          "tr-#{ref.to_s.downcase.gsub(/[^a-z0-9]/, '-')}.yaml"
        when :nz
          ref = item.unique_identifier || item.reference_number || "unknown-#{item.object_id}"
          "nz-#{ref.to_s.downcase.gsub(/[^a-z0-9]/, '-')}.yaml"
        when :eu_vessels
          ref = item.imo_number || item.unique_identifier || "unknown-#{item.object_id}"
          "eu-vessel-#{ref}.yaml"
        when :jp
          ref = item.id || item.unique_identifier || "unknown-#{item.object_id}"
          "jp-#{ref}.yaml"
        when :un_vessels
          ref = item.imo_number || item.unique_identifier || "unknown-#{item.object_id}"
          "un-vessel-#{ref}.yaml"
        else
          "#{item.object_id}.yaml"
        end
      end

      # Get source model class for a source
      # @param source [Symbol] source code
      # @return [Class, nil] the source model class
      def source_model_class_for(source)
        case source
        when :uk
          require_relative '../sources/uk'
          Ammitto::Sources::Uk::Designations
        when :eu
          require_relative '../sources/eu'
          Ammitto::Sources::Eu::Export
        when :un
          require_relative '../sources/un'
          Ammitto::Sources::Un::ConsolidatedList
        when :us
          require_relative '../sources/us'
          Ammitto::Sources::Us::SdnList
        when :wb
          require_relative '../sources/wb'
          Ammitto::Sources::Wb::Response
        when :au
          require_relative '../sources/au'
          Ammitto::Sources::Au::SanctionsList
        when :ca
          require_relative '../sources/ca'
          Ammitto::Sources::Ca::SanctionsList
        when :ch
          require_relative '../sources/ch'
          Ammitto::Sources::Ch::SanctionsList
        when :cn
          require_relative '../sources/cn'
          Ammitto::Sources::Cn::SanctionsList
        when :ru
          require_relative '../sources/ru'
          Ammitto::Sources::Ru::SanctionsList
        when :tr
          require_relative '../sources/tr'
          Ammitto::Sources::Tr::SanctionsList
        when :nz
          require_relative '../sources/nz'
          Ammitto::Sources::Nz::SanctionsList
        when :eu_vessels
          require_relative '../sources/eu_vessels'
          Ammitto::Sources::EuVessels::SanctionsList
        when :jp
          require_relative '../sources/jp'
          Ammitto::Sources::Jp::SanctionsList
        when :un_vessels
          require_relative '../sources/un_vessels'
          Ammitto::Sources::UnVessels::SanctionsList
        end
      rescue LoadError
        nil
      end

      # Get extractor class for source
      # @param source [Symbol] source code
      # @return [Class, nil] extractor class
      def extractor_class_for(source)
        # Load extractors lazily
        require_relative '../extractors/registry'

        Ammitto::Extractors::Registry.get(source)
      rescue LoadError
        nil
      end

      # Get cache directory
      # @return [String]
      def cache_dir
        options[:cache_dir] || File.expand_path('~/.ammitto')
      end

      # Create error result hash
      # @param source [Symbol] source code
      # @param message [String] error message
      # @return [Hash]
      def error_result(source, message)
        {
          code: source,
          status: :error,
          error: message
        }
      end

      # Print summary of results
      # @param results [Array<Hash>] fetch results
      # @return [void]
      def print_summary(results)
        success = results.count { |r| r[:status] == :success }
        failed = results.count { |r| r[:status] == :error }

        puts
        puts "Fetch complete: #{success} succeeded, #{failed} failed"

        return unless failed.positive?

        puts 'Failed sources:'
        results.select { |r| r[:status] == :error }.each do |r|
          puts "  #{r[:code]}: #{r[:error]}"
        end
      end
    end
  end
end
