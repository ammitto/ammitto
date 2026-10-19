# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'
require_relative '../schema/context'
require_relative 'ontology_catalogue'
require_relative 'json_ld_serializer'
require_relative '../person_entity'
require_relative '../organization_entity'
require_relative '../vessel_entity'
require_relative '../name_variant'
require_relative '../tonnage'
require_relative '../ontology/compatibility'

module Ammitto
  module Serialization
    # OntologyExporter exports ontology data for the ontology browser
    #
    # Creates JSON-LD files describing classes, properties, and their relationships
    # for display in the website ontology browser.
    #
    # @example Using the ontology exporter
    #   exporter = OntologyExporter.new
    #   exporter.export('./api/v1/ontology')
    #
    class OntologyExporter
      # Base URI for ontology terms
      BASE_URI = 'https://www.ammitto.org/ontology'

      # Context URL
      CONTEXT_URL = Ammitto::Schema::Context::CONTEXT_URL

      # The output contract is the catalogue source; do not duplicate wire fields here.
      CLASSES = OntologyCatalogue.new.classes.freeze
      PROPERTIES = OntologyCatalogue.new.properties.freeze

      METADATA_CONTEXT = {
        '@vocab' => "#{BASE_URI}/",
        'rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#',
        'rdfs' => 'http://www.w3.org/2000/01/rdf-schema#',
        'owl' => 'http://www.w3.org/2002/07/owl#',
        'xsd' => 'http://www.w3.org/2001/XMLSchema#',
        'label' => 'rdfs:label',
        'comment' => 'rdfs:comment',
        'subClassOf' => { '@id' => 'rdfs:subClassOf', '@type' => '@id' },
        'domain' => { '@id' => 'rdfs:domain', '@type' => '@id' },
        'range' => { '@id' => 'rdfs:range', '@type' => '@id' },
        'usages' => { '@id' => "#{BASE_URI}/usages", '@type' => '@json' },
        'properties' => { '@id' => "#{BASE_URI}/properties", '@type' => '@id', '@container' => '@set' },
        'equivalentClass' => { '@id' => 'owl:equivalentClass', '@type' => '@id' },
        'equivalentProperty' => { '@id' => 'owl:equivalentProperty', '@type' => '@id' }
      }.freeze

      # Entity type info for hierarchy
      ENTITY_TYPES = {
        'person' => { name: 'Person', icon: 'user', color: '#3b82f6' },
        'organization' => { name: 'Organization', icon: 'building', color: '#10b981' },
        'vessel' => { name: 'Vessel', icon: 'ship', color: '#8b5cf6' },
        'aircraft' => { name: 'Aircraft', icon: 'plane', color: '#f59e0b' }
      }.freeze

      # Initialize with optional entity counts
      # @param entity_counts [Hash] counts by entity type
      def initialize(entity_counts = {})
        @entity_counts = entity_counts
      end

      # Set entity counts
      # @param counts [Hash] counts by entity type
      attr_writer :entity_counts

      # Export ontology data to output directory
      # @param output_dir [String] output directory path
      # @return [void]
      def export(output_dir)
        @output_paths = []
        ontology_dir = File.join(output_dir, 'ontology')
        FileUtils.mkdir_p(ontology_dir)

        export_classes(ontology_dir)
        export_properties(ontology_dir)
        export_hierarchy(ontology_dir)
        export_examples(ontology_dir)

        puts "Exported ontology data to #{ontology_dir}"
      end

      # @return [Array<String>] artifact paths written by the last export
      attr_reader :output_paths

      private

      def write_json(path, data)
        File.write(path, JSON.pretty_generate(data))
        @output_paths << File.expand_path(path)
      end

      # Export classes.jsonld
      # @param dir [String] ontology directory
      def export_classes(dir)
        classes_graph = CLASSES.map do |cls|
          class_node = {
            '@id' => "#{BASE_URI}/#{cls[:id]}",
            '@type' => 'rdfs:Class',
            'label' => cls[:label],
            'comment' => cls[:comment],
            'equivalentClass' => OntologyCatalogue.publication_iri(cls[:id])
          }
          class_node['subClassOf'] = "#{BASE_URI}/#{cls[:parent]}" if cls[:parent]
          class_node['properties'] = cls[:properties].map { |p| "#{BASE_URI}/#{p}" } if cls[:properties]
          class_node
        end

        data = {
          '@context' => METADATA_CONTEXT,
          '@graph' => classes_graph
        }

        write_json(File.join(dir, 'classes.jsonld'), data)
      end

      # Export properties.jsonld
      # @param dir [String] ontology directory
      def export_properties(dir)
        properties_graph = PROPERTIES.map do |prop|
          property_node = {
            '@id' => "#{BASE_URI}/#{prop[:id]}",
            '@type' => 'rdf:Property',
            'label' => prop[:label],
            'comment' => prop[:comment],
            'equivalentProperty' => OntologyCatalogue.publication_iri(prop[:id])
          }
          property_node['usages'] = prop[:usages].map do |usage|
            usage.merge(class: "#{BASE_URI}/#{usage[:class]}", range: usage[:range] && map_range(usage[:range])).compact
          end
          property_node['domain'] = "#{BASE_URI}/#{prop[:domain]}" if prop[:domain]
          property_node['range'] = map_range(prop[:range]) if prop[:range]
          property_node['isArray'] = true if prop[:array]
          property_node
        end

        data = {
          '@context' => METADATA_CONTEXT,
          '@graph' => properties_graph
        }

        write_json(File.join(dir, 'properties.jsonld'), data)
      end

      # Map range type to URI
      # @param range [String] range type
      # @return [String] URI or XSD type
      def map_range(range)
        case range
        when 'string', 'integer', 'number', 'date', 'boolean', 'gYear'
          range = 'decimal' if range == 'number'
          "http://www.w3.org/2001/XMLSchema##{range}"
        else
          "#{BASE_URI}/#{range}"
        end
      end

      # Export hierarchy.json
      # @param dir [String] ontology directory
      def export_hierarchy(dir)
        hierarchy = {
          name: 'Entity',
          label: 'Entity',
          count: @entity_counts.values.sum,
          children: build_entity_type_hierarchy
        }

        # Add supporting classes
        supporting = CLASSES.reject { |cls| cls[:id] == 'Entity' || cls[:parent] == 'Entity' }.map do |cls|
          { name: cls[:id], label: cls[:label], children: [] }
        end

        full_hierarchy = {
          name: 'AmmittoOntology',
          label: 'Ammitto Ontology',
          children: [hierarchy] + supporting.map { |s| s.merge(count: 0) }
        }

        write_json(File.join(dir, 'hierarchy.json'), full_hierarchy)
      end

      # Build entity type hierarchy with counts
      # @return [Array<Hash>] entity type nodes
      def build_entity_type_hierarchy
        ENTITY_TYPES.map do |code, info|
          {
            name: "#{code.capitalize}Entity",
            label: info[:name],
            code: code,
            count: @entity_counts[code] || 0,
            icon: info[:icon],
            color: info[:color],
            children: []
          }
        end
      end

      # Export example files
      # @param dir [String] ontology directory
      def export_examples(dir)
        examples_dir = File.join(dir, 'examples')
        FileUtils.mkdir_p(examples_dir)

        export_person_example(examples_dir)
        export_organization_example(examples_dir)
        export_vessel_example(examples_dir)
      end

      # Use the public serializer so examples share the actual publication wire.
      def export_person_example(dir)
        attributes = example_attributes('person', 'DOE, John').merge(
          birth_info: [BirthInfo.new(date: '1970-01-15', country: 'Example Country', country_iso_code: 'XX')],
          nationalities: ['Example Country'],
          identifications: [Identification.new(type: 'passport', number: 'EXAMPLE123')]
        )
        write_example(dir, 'person', PersonEntity.new(attributes))
      end

      def export_organization_example(dir)
        attributes = example_attributes('organization', 'EXAMPLE CORPORATION LTD').merge(
          addresses: [Address.new(street: '123 Example St', city: 'Example City', country_iso_code: 'XX')]
        )
        write_example(dir, 'organization', OrganizationEntity.new(attributes))
      end

      def export_vessel_example(dir)
        attributes = example_attributes('vessel', 'EXAMPLE VESSEL').merge(
          imo_number: '1234567', mmsi: '123456789', flag_state: 'Example Flag State',
          tonnage: Tonnage.new(gross_tonnage: 50_000), call_sign: 'ABCD1'
        )
        write_example(dir, 'vessel', VesselEntity.new(attributes))
      end

      def example_attributes(type, name)
        {
          id: "https://www.ammitto.org/entity/example/#{type}",
          entity_type: type,
          names: [NameVariant.new(full_name: name, is_primary: true)],
          sanction_entry_ids: ["https://www.ammitto.org/entry/example/#{type}"]
        }
      end

      def write_example(dir, type, entity)
        write_json(File.join(dir, "#{type}.jsonld"), JsonLdSerializer.new.serialize_entity(Ontology::Compatibility.canonical(entity)))
      end
    end
  end
end
