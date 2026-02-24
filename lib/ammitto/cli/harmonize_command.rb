# frozen_string_literal: true

require 'fileutils'
require 'yaml'
require 'json'

module Ammitto
  module Cmd
    # Harmonize command - transform YAML source data to JSON-LD
    #
    # Reads YAML files from source directories, transforms them using
    # transformers, and exports as JSON-LD.
    class HarmonizeCommand
      # @return [Hash] command options
      attr_reader :options

      # @return [Array<Symbol>] sources to harmonize
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
          puts 'No sources to harmonize. Specify sources or use --all.'
          return
        end

        harmonize_all
      end

      private

      # Normalize source codes
      # @param sources [Array<String>]
      # @return [Array<Symbol>]
      def normalize_sources(sources)
        if options[:all]
          Config::Defaults::ALL_SOURCES
        elsif sources.empty?
          # Default to first source if none specified
          [:uk]
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

      # Harmonize all sources
      # @return [void]
      def harmonize_all
        results = []

        @sources.each do |source|
          results << harmonize_source(source)
        end

        # Create combined file if requested
        create_combined_output if options[:combine] && results.length > 1

        print_summary(results)
      end

      # Harmonize a single source
      # @param source [Symbol] source code
      # @return [Hash] harmonize result
      def harmonize_source(source)
        puts "[#{source}] Harmonizing..." if options[:verbose]

        input_dir = find_input_dir(source)
        unless input_dir
          puts "[#{source}] No input directory found. Run 'ammitto fetch' first." if options[:verbose]
          return { code: source, status: :error, error: 'No input directory found' }
        end

        # Load YAML files
        yaml_files = Dir.glob(File.join(input_dir, 'entities', '*.yaml'))
        yaml_files = Dir.glob(File.join(input_dir, '*.yaml')) if yaml_files.empty?

        # Filter out metadata files (starting with _)
        yaml_files = yaml_files.reject { |f| File.basename(f).start_with?('_') }

        return { code: source, status: :error, error: 'No YAML files found' } if yaml_files.empty?

        # Parse and transform
        entities = []
        entries = []

        yaml_files.each do |file|
          data = YAML.load_file(file)
          next unless data

          begin
            result = transform_data(source, data)
            entities << result[:entity] if result[:entity]
            entries << result[:entry] if result[:entry]
          rescue => e
            puts "[#{source}] Error processing #{File.basename(file)}: #{e.message}" if options[:verbose]
          end
        end

        # Write JSON-LD output
        output_dir = options[:output_dir] || './api/v1'
        output_file = File.join(output_dir, 'sources', "#{source}.jsonld")

        FileUtils.mkdir_p(File.dirname(output_file))
        write_jsonld(output_file, entities, entries)

        puts "[#{source}] Harmonized #{entities.length} entities to #{output_file}" if options[:verbose]

        { code: source, status: :success, entities: entities.length, entries: entries.length }
      rescue StandardError => e
        puts "[#{source}] ERROR: #{e.message}" if options[:verbose]
        { code: source, status: :error, error: e.message }
      end

      # Find input directory for source
      # @param source [Symbol] source code
      # @return [String, nil] input directory path
      def find_input_dir(source)
        # Check specified input_dir
        if options[:input_dir]
          return File.join(options[:input_dir], source.to_s) if Dir.exist?(File.join(options[:input_dir], source.to_s))
          return options[:input_dir] if Dir.exist?(options[:input_dir])
        end

        # Check sources_dir
        if options[:sources_dir]
          # First check for processed/ directory
          processed_path = File.join(options[:sources_dir], "data-#{source}", 'processed')
          return processed_path if Dir.exist?(processed_path)

          # Then check for raw/{date} directory
          source_path = File.join(options[:sources_dir], "data-#{source}", 'raw')
          return find_latest_subdir(source_path) if Dir.exist?(source_path)
        end

        # Check default cache location
        cache_raw = File.join(cache_dir, 'raw', source.to_s)
        return find_latest_subdir(cache_raw) if Dir.exist?(cache_raw)

        nil
      end

      # Find latest subdirectory (by date)
      # @param base_dir [String] base directory
      # @return [String, nil] latest subdirectory
      def find_latest_subdir(base_dir)
        return nil unless Dir.exist?(base_dir)

        subdirs = Dir.children(base_dir).select do |child|
          path = File.join(base_dir, child)
          Dir.exist?(path) && child.match?(/^\d{4}-\d{2}-\d{2}$/)
        end.sort.reverse

        return nil if subdirs.empty?

        File.join(base_dir, subdirs.first)
      end

      # Transform data using appropriate transformer
      # @param source [Symbol] source code
      # @param data [Hash] source data
      # @return [Hash] { entity: Hash, entry: Hash }
      def transform_data(source, data)
        require_relative '../transformers/registry'

        transformer = Ammitto::Transformers::Registry.get(source)
        return { entity: nil, entry: nil } unless transformer

        # Transform based on source
        case source
        when :uk
          transform_uk(transformer, data)
        when :eu
          transform_eu(transformer, data)
        when :un
          transform_un(transformer, data)
        when :us
          transform_us(transformer, data)
        when :wb
          transform_wb(transformer, data)
        when :au
          transform_au(transformer, data)
        when :ca
          transform_ca(transformer, data)
        when :ch
          transform_ch(transformer, data)
        when :cn
          transform_cn(transformer, data)
        when :ru
          transform_ru(transformer, data)
        when :nz
          transform_nz(transformer, data)
        when :tr
          transform_tr(transformer, data)
        when :eu_vessels
          transform_eu_vessels(transformer, data)
        when :jp
          transform_jp(transformer, data)
        when :un_vessels
          transform_un_vessels(transformer, data)
        else
          { entity: nil, entry: nil }
        end
      end

      # Transform UK data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_uk(transformer, data)
        require_relative '../sources/uk/designation'

        designation = Ammitto::Sources::Uk::Designation.from_yaml(data.to_yaml)
        result = transformer.transform(designation)

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Transform EU data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_eu(transformer, data)
        require_relative '../sources/eu/sanction_entity'

        entity = Ammitto::Sources::Eu::SanctionEntity.from_yaml(data.to_yaml)
        result = transformer.transform(entity)

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Transform UN data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_un(transformer, data)
        require_relative '../sources/un/individual'
        require_relative '../sources/un/entity'

        # Determine if individual or entity based on presence of person-specific fields
        # UN data uses snake_case in YAML (first_name, not firstName)
        is_individual = data.key?('gender') ||
                        data.key?('date_of_birth') ||
                        data.key?('place_of_birth') ||
                        data.key?('documents') ||
                        data.key?('nationalities') ||
                        data.key?('fourth_name')

        if is_individual
          source = Ammitto::Sources::Un::Individual.from_yaml(data.to_yaml)
          result = transformer.transform_individual(source)
        else
          source = Ammitto::Sources::Un::Entity.from_yaml(data.to_yaml)
          result = transformer.transform_entity(source)
        end

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Transform US data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_us(transformer, data)
        require_relative '../sources/us/sdn_entry'

        sdn_entry = Ammitto::Sources::Us::SdnEntry.from_yaml(data.to_yaml)
        result = transformer.transform(sdn_entry)

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Transform WB data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_wb(transformer, data)
        require_relative '../sources/wb/sanctioned_firm'

        firm = Ammitto::Sources::Wb::SanctionedFirm.from_yaml(data.to_yaml)
        result = transformer.transform(firm)

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Transform AU data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_au(transformer, data)
        require_relative '../sources/au/sanctions_list'

        # Check if individual or organization
        source = if data['entity_type'] == 'Individual' || data.key?('dates_of_birth')
                   Ammitto::Sources::Au::Individual.from_yaml(data.to_yaml)
                 else
                   Ammitto::Sources::Au::Organization.from_yaml(data.to_yaml)
                 end
        result = transformer.transform(source)

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Transform CA data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_ca(transformer, data)
        require_relative '../sources/ca/sanctions_list'

        # Check if individual or entity
        if data.key?('first_name') || data.key?('date_of_birth')
          source = Ammitto::Sources::Ca::Individual.from_yaml(data.to_yaml)
          result = transformer.transform_individual(source)
        else
          source = Ammitto::Sources::Ca::Entity.from_yaml(data.to_yaml)
          result = transformer.transform_entity(source)
        end

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Transform CH data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_ch(transformer, data)
        require_relative '../sources/ch/sanctions_list'

        # Check if individual or entity
        if data.key?('full_name') && data.key?('alias_names')
          source = Ammitto::Sources::Ch::Individual.from_yaml(data.to_yaml)
          result = transformer.transform_individual(source)
        else
          source = Ammitto::Sources::Ch::Entity.from_yaml(data.to_yaml)
          result = transformer.transform_entity(source)
        end

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Transform CN data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_cn(transformer, data)
        require_relative '../sources/cn/sanctions_list'

        source = Ammitto::Sources::Cn::SanctionedEntity.from_yaml(data.to_yaml)
        result = transformer.transform(source)

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Transform RU data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_ru(transformer, data)
        require_relative '../sources/ru/sanctions_list'

        source = Ammitto::Sources::Ru::SanctionedEntity.from_yaml(data.to_yaml)
        result = transformer.transform(source)

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Transform NZ data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_nz(transformer, data)
        require_relative '../sources/nz/sanctions_list'

        # Determine type
        case data['type']
        when 'Individual'
          source = Ammitto::Sources::Nz::Individual.from_yaml(data.to_yaml)
        when 'Ship'
          source = Ammitto::Sources::Nz::Ship.from_yaml(data.to_yaml)
        else
          source = Ammitto::Sources::Nz::Entity.from_yaml(data.to_yaml)
        end
        result = transformer.transform(source)

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Transform TR data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_tr(transformer, data)
        require_relative '../sources/tr/sanctions_list'

        source = Ammitto::Sources::Tr::Entity.from_yaml(data.to_yaml)
        result = transformer.transform(source)

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Transform EU Vessels data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_eu_vessels(transformer, data)
        require_relative '../sources/eu_vessels/vessel'

        source = Ammitto::Sources::EuVessels::Vessel.from_yaml(data.to_yaml)
        result = transformer.transform(source)

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Transform JP data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_jp(transformer, data)
        require_relative '../sources/jp/entity'

        source = Ammitto::Sources::Jp::Entity.from_yaml(data.to_yaml)
        result = transformer.transform(source)

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Transform UN Vessels data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_un_vessels(transformer, data)
        require_relative '../sources/un_vessels/vessel'

        source = Ammitto::Sources::UnVessels::Vessel.from_yaml(data.to_yaml)
        result = transformer.transform(source)

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Convert entity to hash
      # @param entity [Object] entity object
      # @return [Hash]
      def entity_to_hash(entity)
        return {} unless entity

        begin
          hash = entity.respond_to?(:to_hash) ? entity.to_hash : entity.to_h
          compact_hash(hash)
        rescue => e
          puts "Error converting entity to hash: #{e.message}" if options[:verbose]
          {}
        end
      end

      # Convert entry to hash
      # @param entry [Object] entry object
      # @return [Hash]
      def entry_to_hash(entry)
        return {} unless entry

        begin
          hash = entry.respond_to?(:to_hash) ? entry.to_hash : entry.to_h
          compact_hash(hash)
        rescue => e
          puts "Error converting entry to hash: #{e.message}" if options[:verbose]
          {}
        end
      end

      # Remove nil values from hash recursively
      # @param hash [Hash] hash to compact
      # @return [Hash]
      def compact_hash(hash)
        return hash unless hash.is_a?(Hash)

        hash.each_with_object({}) do |(k, v), result|
          next if v.nil?

          result[k] = case v
                      when Hash
                        compact_hash(v)
                      when Array
                        v.map { |item| item.is_a?(Hash) ? compact_hash(item) : item }.compact
                      else
                        v
                      end
        end
      end

      # Write JSON-LD output file
      # @param output_file [String] output file path
      # @param entities [Array<Hash>] entities
      # @param entries [Array<Hash>] entries
      # @return [void]
      def write_jsonld(output_file, entities, entries)
        graph = []

        entities.each do |entity|
          graph << entity unless entity.empty?
        end

        entries.each do |entry|
          graph << entry unless entry.empty?
        end

        output = {
          '@context' => 'https://www.ammitto.org/ontology/context.jsonld',
          '@graph' => graph
        }

        File.write(output_file, JSON.pretty_generate(output))
      end

      # Create combined output file
      # @return [void]
      def create_combined_output
        output_dir = options[:output_dir] || './api/v1'
        all_file = File.join(output_dir, 'all.jsonld')

        all_graph = []

        @sources.each do |source|
          source_file = File.join(output_dir, 'sources', "#{source}.jsonld")
          next unless File.exist?(source_file)

          data = JSON.parse(File.read(source_file))
          graph = data['@graph'] || []
          all_graph.concat(graph)
        end

        return if all_graph.empty?

        output = {
          '@context' => 'https://www.ammitto.org/ontology/context.jsonld',
          '@graph' => all_graph
        }

        File.write(all_file, JSON.pretty_generate(output))
        puts "[all] Combined output written to #{all_file}" if options[:verbose]
      end

      # Get cache directory
      # @return [String]
      def cache_dir
        options[:cache_dir] || File.expand_path('~/.ammitto')
      end

      # Print summary of results
      # @param results [Array<Hash>] harmonize results
      # @return [void]
      def print_summary(results)
        success = results.count { |r| r[:status] == :success }
        failed = results.count { |r| r[:status] == :error }

        puts
        puts "Harmonize complete: #{success} succeeded, #{failed} failed"

        return unless failed.positive?

        puts 'Failed sources:'
        results.select { |r| r[:status] == :error }.each do |r|
          puts "  #{r[:code]}: #{r[:error]}"
        end
      end
    end
  end
end
