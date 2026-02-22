# frozen_string_literal: true

require 'json'

module Ammitto
  module Serialization
    # RDF Serializer for multiple output formats
    #
    # Supports JSON-LD, Turtle, N-Triples, and RDF/XML formats.
    #
    # @example Basic usage
    #   serializer = RdfSerializer.new(entities)
    #   jsonld = serializer.serialize(:jsonld)
    #   turtle = serializer.serialize(:ttl)
    #
    class RdfSerializer
      # Supported formats with file extensions and MIME types
      FORMATS = {
        jsonld: { extension: '.jsonld', mime: 'application/ld+json' },
        ttl: { extension: '.ttl', mime: 'text/turtle' },
        nt: { extension: '.nt', mime: 'application/n-triples' },
        rdfxml: { extension: '.rdf', mime: 'application/rdf+xml' }
      }.freeze

      # @return [Array<Hash>] entities to serialize
      attr_reader :entities

      # @return [Hash] JSON-LD context
      attr_reader :context

      # Initialize serializer
      # @param entities [Array<Hash>] entities to serialize
      # @param context [Hash, nil] custom context
      def initialize(entities, context: nil)
        @entities = Array(entities)
        @context = context || default_context
      end

      # Serialize to specified format
      # @param format [Symbol] format (:jsonld, :ttl, :nt, :rdfxml)
      # @return [String] serialized output
      def serialize(format)
        case format
        when :jsonld
          serialize_jsonld
        when :ttl
          serialize_turtle
        when :nt
          serialize_ntriples
        when :rdfxml
          serialize_rdfxml
        else
          raise ArgumentError, "Unknown format: #{format}"
        end
      end

      private

      # Serialize to JSON-LD format
      # @return [String] JSON-LD output
      def serialize_jsonld
        output = {
          '@context' => @context,
          '@graph' => @entities
        }
        JSON.pretty_generate(output)
      end

      # Serialize to Turtle format
      # @return [String] Turtle output
      def serialize_turtle
        require 'rdf'
        require 'rdf/turtle'

        graph = build_rdf_graph
        graph.dump(:turtle, prefixes: prefixes)
      rescue LoadError
        fallback_turtle
      end

      # Serialize to N-Triples format
      # @return [String] N-Triples output
      def serialize_ntriples
        require 'rdf'

        graph = build_rdf_graph
        graph.dump(:ntriples)
      rescue LoadError
        fallback_ntriples
      end

      # Serialize to RDF/XML format
      # @return [String] RDF/XML output
      def serialize_rdfxml
        require 'rdf'

        graph = build_rdf_graph
        graph.dump(:rdfxml)
      rescue LoadError
        fallback_rdfxml
      end

      # Build RDF graph from entities
      # @return [RDF::Graph]
      def build_rdf_graph
        require 'rdf'

        graph = RDF::Graph.new

        @entities.each do |entity|
          add_entity_to_graph(graph, entity)
        end

        graph
      end

      # Add entity to RDF graph
      # @param graph [RDF::Graph]
      # @param entity [Hash]
      # @return [void]
      def add_entity_to_graph(graph, entity)
        require 'rdf'

        subject = RDF::URI(entity['@id'])

        # Add type
        type = entity['@type']
        graph << [subject, RDF.type, RDF::URI("https://www.ammitto.org/ontology/#{type}")] if type

        # Add properties
        entity.each do |key, value|
          next if key.start_with?('@')
          next if value.nil?

          predicate = RDF::URI("https://www.ammitto.org/ontology/#{key}")

          case value
          when Array
            value.each do |v|
              add_value_to_graph(graph, subject, predicate, v)
            end
          else
            add_value_to_graph(graph, subject, predicate, value)
          end
        end
      end

      # Add value to RDF graph
      # @param graph [RDF::Graph]
      # @param subject [RDF::Resource]
      # @param predicate [RDF::URI]
      # @param value [Object]
      # @return [void]
      def add_value_to_graph(graph, subject, predicate, value)
        require 'rdf'

        case value
        when Hash
          # Blank node
          bnode = RDF::Node.new
          graph << [subject, predicate, bnode]
          value.each do |k, v|
            next if k.start_with?('@')

            p = RDF::URI("https://www.ammitto.org/ontology/#{k}")
            add_value_to_graph(graph, bnode, p, v)
          end
        when true, false
          graph << [subject, predicate, RDF::Literal::Boolean.new(value)]
        when Integer
          graph << [subject, predicate, RDF::Literal::Integer.new(value)]
        else
          graph << [subject, predicate, RDF::Literal.new(value.to_s)]
        end
      end

      # Fallback Turtle serialization (without rdf gem)
      # @return [String]
      def fallback_turtle
        <<~TTL
          @prefix amt: <https://www.ammitto.org/ontology/> .
          @prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
          @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
          @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

          # Note: Install 'rdf-turtle' gem for proper serialization
          # This is a placeholder output

          #{entities.map { |e| "# Entity: #{e['@id']}" }.join("\n")}
        TTL
      end

      # Fallback N-Triples serialization
      # @return [String]
      def fallback_ntriples
        <<~NT
          # N-Triples output
          # Note: Install 'rdf' gem for proper serialization
          #{entities.map { |e| "# #{e['@id']}" }.join("\n")}
        NT
      end

      # Fallback RDF/XML serialization
      # @return [String]
      def fallback_rdfxml
        <<~RDFXML
          <?xml version="1.0" encoding="UTF-8"?>
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                   xmlns:amt="https://www.ammitto.org/ontology/">
            <!-- Note: Install 'rdf' gem for proper serialization -->
            #{entities.map { |e| "<!-- Entity: #{e['@id']} -->" }.join("\n    ")}
          </rdf:RDF>
        RDFXML
      end

      # Default JSON-LD context
      # @return [Hash]
      def default_context
        {
          '@version' => 1.1,
          'amt' => 'https://www.ammitto.org/ontology/',
          'amt-ent' => 'https://www.ammitto.org/entity/',
          'rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#',
          'rdfs' => 'http://www.w3.org/2000/01/rdf-schema#',
          'xsd' => 'http://www.w3.org/2001/XMLSchema#'
        }
      end

      # Prefixes for Turtle output
      # @return [Hash]
      def prefixes
        {
          amt: 'https://www.ammitto.org/ontology/',
          rdf: 'http://www.w3.org/1999/02/22-rdf-syntax-ns#',
          rdfs: 'http://www.w3.org/2000/01/rdf-schema#',
          xsd: 'http://www.w3.org/2001/XMLSchema#'
        }
      end
    end
  end
end
