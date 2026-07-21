# frozen_string_literal: true

# Neo4j Graph Adapter for Ammitto Ontology
#
# This module provides Neo4j-specific metadata for ontology classes.
# The ontology classes define their own labels, properties, and relationships.
#
# Each class that includes this module gains:
# - neo4j_labels: Array of labels for this node type
# - neo4j_properties: Properties to store on the node
# - neo4j_relationships: Relationships to create
#
# This makes the ontology CLASSES the schema, not a separate YAML file.
#
# SINGLE SOURCE OF TRUTH:
# The neo4j_property declarations drive BOTH import and export.
# This guarantees 100% coverage between what's imported and exported.

module Ammitto
  module Ontology
    module Neo4jAdapter
      # Extend class with Neo4j mapping capabilities
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Define Neo4j labels for this class
        def neo4j_labels(*labels)
          @neo4j_labels = labels if labels.any?
          @neo4j_labels || [name.demodulize.gsub(/Entity$/, '')]
        end

        # Get all Neo4j labels including inherited ones
        def all_neo4j_labels
          labels = neo4j_labels.dup
          labels = superclass.all_neo4j_labels + labels if superclass.respond_to?(:all_neo4j_labels)
          labels.uniq
        end

        # Define which attributes are node properties (vs relationships)
        def neo4j_property_attributes
          @neo4j_property_attributes ||= []
        end

        def neo4j_property(*attrs)
          neo4j_property_attributes.concat(attrs)
        end

        # Get all Neo4j properties including inherited ones
        def all_neo4j_property_attributes
          props = neo4j_property_attributes.dup
          props = superclass.all_neo4j_property_attributes + props if superclass.respond_to?(:all_neo4j_property_attributes)
          props.uniq
        end

        # Define relationship mappings
        def neo4j_relationship_mappings
          @neo4j_relationship_mappings ||= {}
        end

        def neo4j_relationship(name, type:, target_class:, target_key:)
          neo4j_relationship_mappings[name] = {
            type: type,
            target_class: target_class,
            target_key: target_key
          }
        end

        # Get all Neo4j relationships including inherited ones
        def all_neo4j_relationship_mappings
          mappings = neo4j_relationship_mappings.dup
          mappings = superclass.all_neo4j_relationship_mappings.merge(mappings) if superclass.respond_to?(:all_neo4j_relationship_mappings)
          mappings
        end

        # Load an entity from a Neo4j record (hash with string keys)
        # @param record [Hash] Neo4j node properties
        # @return [Entity] the loaded entity
        def from_neo4j_record(record)
          return nil if record.nil?

          instance = new

          # Load id first if the class has an id attribute
          instance.id = record['id'] if instance.respond_to?(:id=) && record.key?('id')

          all_neo4j_property_attributes.each do |attr|
            key = attr.to_s
            if record.key?(key)
              value = deserialize_value(record[key], attr)
              instance.send("#{attr}=", value) if instance.respond_to?("#{attr}=")
            end
          end
          instance
        end

        # Find an entity by ID in Neo4j
        # @param session [Neo4j::Session] the Neo4j session
        # @param id [String] the entity ID
        # @return [Entity, nil] the found entity or nil
        def neo4j_find(session, id)
          labels_str = all_neo4j_labels.map { |l| ":#{l}" }.join
          query = "MATCH (n#{labels_str} {id: $id}) RETURN n"
          result = session.run(query, id: id)
          return nil if result.empty?

          record = result.first['n']
          from_neo4j_record(record)
        end

        # Find all entities of this type in Neo4j
        # @param session [Neo4j::Session] the Neo4j session
        # @return [Array<Entity>] array of entities
        def neo4j_find_all(session)
          labels_str = all_neo4j_labels.map { |l| ":#{l}" }.join
          query = "MATCH (n#{labels_str}) RETURN n"
          result = session.run(query)
          result.map do |row|
            from_neo4j_record(row['n'])
          end.compact
        end

        private

        # Deserialize a value from Neo4j storage format
        def deserialize_value(value, attr)
          return nil if value.nil?

          # Check if attribute type is Date
          if method_defined?(attr) &&
             method_defined?(attr) &&
             respond_to?(:attribute_types) &&
             attribute_types[attr] == :date && value.is_a?(String)
            return Date.parse(value)
          end

          value
        end
      end

      # Instance methods

      # Get Neo4j labels for this instance
      def neo4j_labels
        self.class.all_neo4j_labels
      end

      # Get properties for Neo4j node
      # Uses the class-level neo4j_property_attributes to determine
      # which attributes to include
      def neo4j_properties
        props = {}
        # Include id if the object has one (entities have id, value objects don't)
        props[:id] = id if respond_to?(:id) && !id.nil?

        self.class.all_neo4j_property_attributes.each do |attr|
          next if attr == :id # Already included above

          value = send(attr) if respond_to?(attr)
          props[attr] = serialize_value(value) unless value.nil?
        end
        props
      end

      # Alias for backwards compatibility
      alias to_neo4j_properties neo4j_properties

      # Get Neo4j node representation (labels + properties)
      # @return [Hash] with :labels and :properties keys
      def to_neo4j_node
        {
          labels: neo4j_labels,
          properties: neo4j_properties
        }
      end

      # Get relationships for this entity
      def neo4j_relationships
        self.class.all_neo4j_relationship_mappings.transform_values do |mapping|
          related = send(mapping[:name] || mapping.keys.first)
          next nil if related.nil?

          if related.is_a?(Array)
            related.map { |r| extract_target_id(r, mapping) }
          else
            extract_target_id(related, mapping)
          end
        end.compact
      end

      # Create Cypher MERGE statement for this node
      def neo4j_merge_cypher
        labels = neo4j_labels.join(':')
        props = neo4j_properties

        set_clauses = props.except(:id).map do |key, _value|
          "n.#{key} = $#{key}"
        end

        <<~CYPHER
          MERGE (n:#{labels} {id: $id})
          #{"SET #{set_clauses.join(', ')}" if set_clauses.any?}
        CYPHER
      end

      # Convert to JSON-LD format
      # @return [Hash] JSON-LD representation
      def to_jsonld
        {
          '@context' => jsonld_context,
          '@id' => id,
          '@type' => jsonld_type
        }.merge(jsonld_properties)
      end

      private

      def serialize_value(value)
        case value
        when Date, Time
          value.to_s
        when Array
          value.map { |v| serialize_value(v) }.join('; ')
        when Hash
          value.to_json
        else
          value
        end
      end

      def extract_target_id(obj, mapping)
        return obj unless obj.is_a?(Lutaml::Model::Serializable)

        key = mapping[:target_key] || :id
        obj.send(key)
      end

      # Get JSON-LD context for this entity
      def jsonld_context
        # Use the ontology's JSON-LD context if available
        if defined?(Ammitto::Ontology::JsonLdContext)
          Ammitto::Ontology::JsonLdContext.generate
        else
          default_jsonld_context
        end
      end

      # Default JSON-LD context
      def default_jsonld_context
        {
          '@vocab' => 'https://www.ammitto.org/ontology/',
          'id' => '@id',
          'type' => '@type'
        }
      end

      # Get the JSON-LD type (most specific label)
      # For PersonEntity, returns "Person" not "Entity"
      def jsonld_type
        labels = neo4j_labels
        # Remove the base "Entity" label to get the specific type
        specific_labels = labels.reject { |l| l == 'Entity' }
        specific_labels.first || labels.first
      end

      # Get properties for JSON-LD serialization
      def jsonld_properties
        props = {}
        self.class.all_neo4j_property_attributes.each do |attr|
          next if attr == :id # Already in @id

          value = send(attr) if respond_to?(attr)
          next if value.nil?

          # Handle complex types
          props[attr] = if value.is_a?(Array) && value.first.is_a?(Lutaml::Model::Serializable)
                          value.map(&:to_hash)
                        elsif value.is_a?(Lutaml::Model::Serializable)
                          value.to_hash
                        else
                          serialize_value(value)
                        end
        end
        props
      end
    end
  end
end
