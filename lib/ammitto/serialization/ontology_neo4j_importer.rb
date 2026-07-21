# frozen_string_literal: true

# Neo4j Direct Importer - Ontology-Driven
#
# This importer uses the ontology classes AS the schema.
# No hardcoded case/when - the classes define their own Neo4j mapping.
#
# Usage:
#   importer = Ammitto::Serialization::OntologyNeo4jImporter.new
#   importer.import_all

require 'neo4j/driver'
require 'yaml'
require_relative '../ontology'

module Ammitto
  module Serialization
    class OntologyNeo4jImporter
      include Neo4j::Driver

      # Schema is defined by the ONTOLOGY CLASSES, not hardcoded
      # Each class uses neo4j_labels, neo4j_property, neo4j_relationship

      def initialize(uri: 'neo4j://localhost:7687', username: 'neo4j', password: 'password')
        @uri = uri
        @username = username
        @password = password
        @driver = nil
        @session = nil
        @stats = { nodes: {}, relationships: {} }
      end

      def connect
        @driver = GraphDatabase.driver(@uri, AuthTokens.basic(@username, @password))
        @session = @driver.session
        puts "Connected to Neo4j at #{@uri}"
      end

      def disconnect
        @session&.close
        @driver&.close
      end

      # Import all sources
      def import_all(base_dir = nil)
        base_dir ||= detect_base_dir

        connect
        create_schema

        # Import authorities - defined in Ontology module
        import_authorities

        # Find and import all processed data
        find_and_import_sources(base_dir)

        disconnect
        print_stats
      end

      private

      def detect_base_dir
        # Check multiple possible locations
        candidates = [
          File.expand_path('../data', __dir__),
          File.expand_path('../../data', __dir__),
          '/Users/mulgogi/src/ammitto/data',
          '/Users/mulgogi/src/ammitto/data-au/..'
        ]

        candidates.each do |dir|
          return dir if Dir.exist?(dir) && Dir.glob(File.join(dir, 'data-*')).any?
        end

        # Default to parent of ammitto
        File.expand_path('..', __dir__)
      end

      # Schema is derived from ontology classes
      def create_schema
        puts 'Creating schema from ontology...'

        # Create constraints for all entity types
        constraints = []

        # Entity base constraint
        constraints << 'CREATE CONSTRAINT IF NOT EXISTS FOR (n:Entity) REQUIRE n.id IS UNIQUE'

        constraints.each { |c| @session.run(c) }

        # Create indexes for common queries
        indexes = [
          'CREATE INDEX IF NOT EXISTS FOR (n:Entity) ON (n.source)',
          'CREATE INDEX IF NOT EXISTS FOR (n:Entity) ON (n.primary_name)',
          'CREATE INDEX IF NOT EXISTS FOR (n:Entry) ON (n.status)'
        ]

        indexes.each { |i| @session.run(i) }
        puts 'Schema created'
      end

      # Import authorities from Ontology module - no hardcoding!
      def import_authorities
        puts 'Importing authorities from ontology registry...'
        count = 0

        Ammitto::Ontology.authorities.each do |code, authority|
          @session.run(
            'MERGE (a:Authority {code: $code}) SET a.name = $name, a.country_code = $country_code',
            code: code,
            name: authority.name,
            country_code: authority.country_code
          )
          count += 1
        end

        @stats[:nodes]['Authority'] = count
        puts "  Imported #{count} authorities"
      end

      def find_and_import_sources(base_dir)
        sources = Dir.glob(File.join(base_dir, 'data-*'))
        sources.each do |src|
          processed = File.join(src, 'processed')
          next unless Dir.exist?(processed)

          source_code = File.basename(src).sub('data-', '')
          puts "\n=== Importing #{source_code} ==="

          import_source(processed, source_code)
        end
      end

      def import_source(dir, source)
        entities_dir = File.join(dir, 'entities')
        return unless Dir.exist?(entities_dir)

        # Get entity class from ontology - use the ontology to determine type

        Dir.glob(File.join(entities_dir, '*.yaml')).each do |f|
          data = YAML.load_file(f)
          next unless data.is_a?(Hash)

          # Use ontology to determine entity type - no case/when!
          entity = instantiate_entity(data)
          next unless entity

          save_entity(entity, source)
        end
      end

      # Use ontology factory - NO hardcoded type mapping!
      def instantiate_entity(data)
        type = data['entity_type'] || data['type'] || 'organization'

        # Use the ontology factory - this is the ONLY place we map type strings
        # The factory knows all entity types
        begin
          entity = Ontology::Entities.create(type.to_sym, id: data['id'])

          # Set properties from data
          data.each do |key, value|
            next if %w[id entity_type].include?(key)

            entity.send("#{key}=", value) if entity.respond_to?("#{key}=")
          end

          entity
        rescue StandardError => e
          puts "  Warning: Could not instantiate #{type}: #{e.message}"
          nil
        end
      end

      # Save entity to Neo4j using ontology metadata
      def save_entity(entity, source)
        # Get labels from ontology - no hardcoding!
        labels = entity.class.neo4j_labels
        primary_label = labels.first

        # Get properties from ontology
        props = { id: entity.id, source: source }
        entity.class.neo4j_property_attributes.each do |attr|
          value = entity.send(attr)
          props[attr] = value if value
        end

        # Add primary name if available
        props[:primary_name] = entity.primary_name if entity.respond_to?(:primary_name) && entity.primary_name

        # Create node - labels from ontology
        label_str = labels.join(':')
        set_clauses = props.keys.map { |k| "n.#{k} = $#{k}" }.join(', ')

        @session.run(
          "MERGE (n:#{label_str} {id: $id}) SET #{set_clauses}",
          props
        )

        @stats[:nodes][primary_label] = (@stats[:nodes][primary_label] || 0) + 1

        # Handle relationships defined in ontology
        save_entity_relationships(entity)
      rescue StandardError => e
        puts "  Error saving entity: #{e.message}"
      end

      def save_entity_relationships(entity)
        # Get relationship mappings from ontology class
        mappings = entity.class.neo4j_relationship_mappings

        mappings.each do |attr_name, mapping|
          related = entity.send(attr_name)
          next if related.nil?

          related = [related] unless related.is_a?(Array)

          related.each do |rel|
            target_id = extract_target_id(rel, mapping[:target_key])
            next unless target_id

            # Create relationship
            @session.run(
              "MATCH (e:#{entity.class.neo4j_labels.first} {id: $eid})
               MERGE (t:#{mapping[:target_class]} {id: $tid})
               MERGE (e)-[r:#{mapping[:type]}]->(t)",
              eid: entity.id,
              tid: target_id
            )

            @stats[:relationships][mapping[:type]] = (@stats[:relationships][mapping[:type]] || 0) + 1
          end
        end
      end

      def extract_target_id(obj, key)
        return obj if obj.is_a?(String)

        if obj.respond_to?(key)
          obj.send(key)
        elsif obj.is_a?(Hash)
          obj[key]
        end
      end

      def print_stats
        puts "\n=== Import Statistics ==="
        @stats[:nodes].sort_by { |_, v| -v }.each do |type, count|
          puts "  #{type}: #{count}"
        end
        puts "\nRelationships:"
        @stats[:relationships].sort_by { |_, v| -v }.each do |type, count|
          puts "  #{type}: #{count}"
        end
      end
    end
  end
end
