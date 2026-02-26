# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require 'json'
require 'date'

module Ammitto
  module Exporter
    # Simple YAML to JSON-LD exporter
    #
    # Reads processed YAML files from eu-data/, un-data/, etc.
    # and outputs JSON-LD files to data/api/v1/
    class SimpleExporter
      SOURCE_DIRS = {
        eu: 'eu-data',
        un: 'un-data',
        us: 'us-govt-data',
        wb: 'wb-data'
      }.freeze

      CONTEXT_URL = 'https://ammitto.org/schema/v1/context.jsonld'

      attr_reader :base_dir, :output_dir

      def initialize(base_dir: nil, output_dir: nil)
        @base_dir = base_dir || find_base_dir
        @output_dir = output_dir || File.join(@base_dir, 'data')
      end

      # Export all sources
      def export_all
        results = {}
        all_graph = []

        SOURCE_DIRS.each_key do |code|
          result = export_source(code)
          results[code] = result[:stats]

          if result[:graph]
            all_graph.concat(result[:graph])
            puts "  #{code.upcase}: #{result[:stats][:entities]} entities"
          end
        end

        # Write combined file
        write_combined(all_graph)

        puts "\nTotal: #{all_graph.length} entities exported"
        puts "Output: #{output_dir}/api/v1/"

        results
      end

      # Export a single source
      def export_source(source_code)
        dir = SOURCE_DIRS[source_code]
        return { error: "Unknown source: #{source_code}" } unless dir

        source_path = File.join(base_dir, dir, 'processed')
        return { error: "Directory not found: #{source_path}" } unless Dir.exist?(source_path)

        graph = []
        yaml_files = Dir.glob(File.join(source_path, '*.yaml'))

        yaml_files.each do |yaml_file|
          entity = convert_yaml_file(yaml_file, source_code)
          graph << entity if entity
        end

        # Write source file
        output_path = write_source(source_code, graph)

        {
          stats: { files: yaml_files.length, entities: graph.length },
          graph: graph,
          output: output_path
        }
      end

      private

      def find_base_dir
        # Find the parent directory containing the data repos
        current = File.expand_path('..', __dir__)
        while current != '/'
          return current if Dir.exist?(File.join(current, 'eu-data'))

          current = File.expand_path('..', current)
        end
        Dir.pwd
      end

      def convert_yaml_file(yaml_path, source_code)
        data = YAML.safe_load(File.read(yaml_path), permitted_classes: [Date, Time])
        return nil unless data

        names = data['names'] || []
        return nil if names.empty?

        # Generate entity ID
        ref = data['ref_number'] || names.first
        slug = ref.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')
        entity_id = "https://ammitto.org/entity/#{source_code}/#{slug}"

        # Determine entity type
        entity_type = data['entity_type'] || 'organization'
        type_class = {
          'person' => 'PersonEntity',
          'organization' => 'OrganizationEntity',
          'vessel' => 'VesselEntity',
          'aircraft' => 'AircraftEntity'
        }[entity_type] || 'OrganizationEntity'

        # Build entity
        entity = {
          '@id' => entity_id,
          '@type' => type_class,
          'entityType' => entity_type,
          'names' => build_names(names),
          'source' => source_code.to_s.upcase,
          'sourceReference' => data['ref_number']
        }

        # Add optional fields
        entity['country'] = data['country'] if data['country'] && !data['country'].empty?
        entity['birthDate'] = data['birthdate'] if data['birthdate'] && !data['birthdate'].empty?
        entity['remarks'] = data['remark'] if data['remark'] && !data['remark'].empty?
        entity['contact'] = data['contact'] if data['contact'] && !data['contact'].empty?
        entity['addresses'] = build_addresses(data['address']) if data['address']

        entity.compact
      rescue StandardError => e
        puts "  Warning: Failed to process #{yaml_path}: #{e.message}"
        nil
      end

      def build_names(names_array)
        return [] unless names_array.is_a?(Array)

        names_array.map.with_index do |name, idx|
          {
            '@type' => 'NameVariant',
            'fullName' => name.to_s,
            'isPrimary' => idx.zero?
          }
        end
      end

      def build_addresses(address_data)
        return nil unless address_data.is_a?(Array) && !address_data.empty?

        address_data.map do |addr|
          next unless addr.is_a?(Hash)

          {
            '@type' => 'Address',
            'street' => addr['street'],
            'city' => addr['city'],
            'state' => addr['state'],
            'country' => addr['country'],
            'postalCode' => addr['zip']
          }.compact
        end.compact
      end

      def write_source(source_code, graph)
        FileUtils.mkdir_p(File.join(output_dir, 'api', 'v1', 'sources'))

        json_ld = {
          '@context' => CONTEXT_URL,
          '@graph' => graph
        }

        output_path = File.join(output_dir, 'api', 'v1', 'sources', "#{source_code}.jsonld")
        File.write(output_path, JSON.pretty_generate(json_ld))

        output_path
      end

      def write_combined(graph)
        FileUtils.mkdir_p(File.join(output_dir, 'api', 'v1'))

        json_ld = {
          '@context' => CONTEXT_URL,
          '@graph' => graph
        }

        output_path = File.join(output_dir, 'api', 'v1', 'all.jsonld')
        File.write(output_path, JSON.pretty_generate(json_ld))

        output_path
      end
    end
  end
end
