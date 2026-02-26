# frozen_string_literal: true

require 'json'

module Ammitto
  module Serialization
    # TurtleExporter converts JSON-LD to Turtle (TTL) format
    #
    # This class provides a simple conversion from JSON-LD files to Turtle
    # format for RDF compatibility.
    #
    # @example Converting JSON-LD to Turtle
    #   TurtleExporter.export(
    #     jsonld_path: './api/v1/all.jsonld',
    #     output_path: './api/v1/all.ttl'
    #   )
    #
    class TurtleExporter
      # RDF namespace prefixes
      PREFIXES = {
        ammitto: 'https://www.ammitto.org/ontology/',
        entity: 'https://www.ammitto.org/entity/',
        entry: 'https://www.ammitto.org/entry/',
        instrument: 'https://www.ammitto.org/instrument/',
        regime: 'https://www.ammitto.org/regime/',
        authority: 'https://www.ammitto.org/authority/',
        schema: 'http://schema.org/',
        xsd: 'http://www.w3.org/2001/XMLSchema#',
        rdf: 'http://www.w3.org/1999/02/22-rdf-syntax-ns#',
        rdfs: 'http://www.w3.org/2000/01/rdf-schema#',
        owl: 'http://www.w3.org/2002/07/owl#'
      }.freeze

      # Export JSON-LD to Turtle format
      #
      # @param jsonld_path [String] path to JSON-LD file
      # @param output_path [String] path to output Turtle file
      # @return [void]
      def self.export(jsonld_path:, output_path:)
        new(jsonld_path, output_path).export
      end

      # Initialize the exporter
      # @param jsonld_path [String] path to JSON-LD file
      # @param output_path [String] path to output Turtle file
      def initialize(jsonld_path, output_path)
        @jsonld_path = jsonld_path
        @output_path = output_path
      end

      # Perform the export
      # @return [void]
      def export
        data = JSON.parse(File.read(@jsonld_path))
        turtle = convert_to_turtle(data)
        File.write(@output_path, turtle)
      end

      private

      # Convert JSON-LD data to Turtle format
      # @param data [Hash] JSON-LD data
      # @return [String] Turtle representation
      def convert_to_turtle(data)
        output = []

        # Add prefixes
        output << '@prefix ammitto: <https://www.ammitto.org/ontology/> .'
        output << '@prefix entity: <https://www.ammitto.org/entity/> .'
        output << '@prefix entry: <https://www.ammitto.org/entry/> .'
        output << '@prefix instrument: <https://www.ammitto.org/instrument/> .'
        output << '@prefix regime: <https://www.ammitto.org/regime/> .'
        output << '@prefix authority: <https://www.ammitto.org/authority/> .'
        output << '@prefix schema: <http://schema.org/> .'
        output << '@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .'
        output << '@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .'
        output << '@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .'
        output << '@prefix owl: <http://www.w3.org/2002/07/owl#> .'
        output << ''

        # Process graph or single node
        graph = data['@graph'] || [data]

        graph.each do |node|
          next unless node.is_a?(Hash)

          turtle_node = convert_node(node)
          output << turtle_node if turtle_node
        end

        output.join("\n")
      end

      # Convert a single node to Turtle
      # @param node [Hash] node data
      # @return [String, nil] Turtle representation
      def convert_node(node)
        id = node['@id'] || node['id']
        return nil unless id

        type = node['@type'] || node['type']
        predicates = []

        # Add type
        if type
          type_uri = expand_type(type)
          predicates << "  a #{type_uri}"
        end

        # Add predicates
        node.each do |key, value|
          next if key.start_with?('@')
          next if key == 'id'

          predicate = expand_predicate(key)
          objects = convert_value(value)
          objects.each do |obj|
            predicates << "  #{predicate} #{obj}"
          end
        end

        return nil if predicates.empty?

        "<#{id}>\n#{predicates.join(' ;\n')} ."
      end

      # Expand type to full URI
      # @param type [String] type name
      # @return [String] full URI
      def expand_type(type)
        case type
        when 'PersonEntity', 'OrganizationEntity', 'VesselEntity', 'AircraftEntity',
             'SanctionEntry', 'Authority', 'SanctionRegime', 'LegalInstrument',
             'NameVariant', 'Address', 'BirthInfo', 'Identification'
          "ammitto:#{type}"
        else
          type.start_with?('http') ? "<#{type}>" : "ammitto:#{type}"
        end
      end

      # Expand predicate to full URI
      # @param key [String] predicate key
      # @return [String] full URI
      def expand_predicate(key)
        predicate_map = {
          'entityType' => 'ammitto:entityType',
          'names' => 'ammitto:hasName',
          'sourceReferences' => 'ammitto:hasSourceReference',
          'linkedEntities' => 'ammitto:hasLinkedEntity',
          'sameAs' => 'owl:sameAs',
          'remarks' => 'ammitto:remarks',
          'fullName' => 'ammitto:fullName',
          'firstName' => 'ammitto:firstName',
          'lastName' => 'ammitto:lastName',
          'script' => 'ammitto:script',
          'isPrimary' => 'ammitto:isPrimary',
          'entityId' => 'ammitto:entityId',
          'authority' => 'ammitto:hasAuthority',
          'regime' => 'ammitto:hasRegime',
          'status' => 'ammitto:status',
          'effects' => 'ammitto:hasEffect',
          'legalBases' => 'ammitto:hasLegalBasis',
          'reasons' => 'ammitto:hasReason',
          'period' => 'ammitto:hasPeriod',
          'referenceNumber' => 'ammitto:referenceNumber',
          'name' => 'schema:name',
          'countryCode' => 'ammitto:countryCode',
          'code' => 'ammitto:code',
          'description' => 'schema:description',
          'effectType' => 'ammitto:effectType',
          'scope' => 'ammitto:scope',
          'listedDate' => 'ammitto:listedDate',
          'effectiveDate' => 'ammitto:effectiveDate',
          'expiryDate' => 'ammitto:expiryDate',
          'isIndefinite' => 'ammitto:isIndefinite',
          'lastUpdated' => 'ammitto:lastUpdated'
        }

        predicate_map[key] || "ammitto:#{key}"
      end

      # Convert a value to Turtle object(s)
      # @param value [Object] the value
      # @return [Array<String>] Turtle object representations
      def convert_value(value)
        return [] if value.nil?

        case value
        when Array
          value.flat_map { |v| convert_value(v) }
        when Hash
          if value['@id']
            ["<#{value['@id']}>"]
          elsif value['@type']
            # Inline blank node
            convert_inline_node(value)
          else
            # Simple hash - convert to string representation
            ["\"\"\"#{value.to_json}\"\"\""]
          end
        when TrueClass
          ['"true"^^xsd:boolean']
        when FalseClass
          ['"false"^^xsd:boolean']
        when Integer
          ["\"#{value}\"^^xsd:integer"]
        when Float
          ["\"#{value}\"^^xsd:decimal"]
        when String
          if value.start_with?('http://', 'https://')
            ["<#{value}>"]
          elsif value.match?(/^\d{4}-\d{2}-\d{2}$/)
            ["\"#{value}\"^^xsd:date"]
          elsif value.match?(/^\d{4}-\d{2}-\d{2}T/)
            ["\"#{value}\"^^xsd:dateTime"]
          else
            [escape_string(value)]
          end
        else
          [escape_string(value.to_s)]
        end
      end

      # Convert an inline node to Turtle
      # @param node [Hash] inline node
      # @return [Array<String>] Turtle representation
      def convert_inline_node(node)
        type = node['@type']
        predicates = []

        predicates << "a #{expand_type(type)}" if type

        node.each do |key, value|
          next if key.start_with?('@')

          predicate = expand_predicate(key)
          objects = convert_value(value)
          objects.each do |obj|
            predicates << "#{predicate} #{obj}"
          end
        end

        return ['[]'] if predicates.empty?

        ["[ #{predicates.join(' ; ')} ]"]
      end

      # Escape a string for Turtle
      # @param str [String] the string
      # @return [String] escaped string
      def escape_string(str)
        escaped = str.to_s
                     .gsub('\\', '\\\\')
                     .gsub('"', '\\"')
                     .gsub("\n", '\\n')
                     .gsub("\r", '\\r')
                     .gsub("\t", '\\t')
        "\"#{escaped}\""
      end
    end
  end
end
