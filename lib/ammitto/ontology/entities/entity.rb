# frozen_string_literal: true

require 'lutaml/model'
require_relative '../types'
require_relative '../value_objects'

module Ammitto
  module Ontology
    module Entities
      # Base class for all sanctionable entities
      #
      # Entity is abstract - use PersonEntity, OrganizationEntity,
      # VesselEntity, or AircraftEntity for actual entities.
      #
      # Each entity has a unique URI identifier and can have multiple
      # sanction entries from different authorities.
      #
      # @example Creating an entity
      #   entity = PersonEntity.new(
      #     id: "https://www.ammitto.org/entity/eu/EU.123.45",
      #     entity_type: :person,
      #     names: [NameVariant.new(full_name: "John Doe", is_primary: true)]
      #   )
      #
      class Entity < Lutaml::Model::Serializable
        # Unique URI identifier for the entity
        # @return [String]
        attribute :id, :string

        # Type of entity (person, organization, vessel, aircraft)
        # @return [String]
        attribute :entity_type, :string

        # Source references (which data sources mention this entity)
        # @return [Array<Hash>, nil]
        attribute :source_references, :hash, collection: true

        # Linked entities (relationships to other entities)
        # @return [Array<Hash>, nil]
        attribute :linked_entities, :hash, collection: true

        # Same-as links (same entity in other databases)
        # @return [Array<String>, nil]
        attribute :same_as, :string, collection: true

        # General remarks
        # @return [String, nil]
        attribute :remarks, :string

        # Sanction entries linked to this entity
        # @return [Array, nil]
        attr_reader :sanction_entries

        def initialize(*args)
          super
          @sanction_entries ||= []
        end

        # Add a sanction entry to this entity
        # @param entry [SanctionEntry]
        # @return [void]
        def add_sanction_entry(entry)
          @sanction_entries ||= []
          @sanction_entries << entry
        end

        # Get entity type as symbol
        # @return [Symbol]
        def entity_type_sym
          entity_type&.to_sym
        end

        # Check if this is a person
        # @return [Boolean]
        def person?
          entity_type == 'person'
        end

        # Check if this is an organization
        # @return [Boolean]
        def organization?
          entity_type == 'organization'
        end

        # Check if this is a vessel
        # @return [Boolean]
        def vessel?
          entity_type == 'vessel'
        end

        # Check if this is an aircraft
        # @return [Boolean]
        def aircraft?
          entity_type == 'aircraft'
        end

        # Get primary name (first name marked as primary, or first name)
        # @return [String, nil]
        def primary_name
          nil # Override in subclasses
        end

        # Convert to hash for JSON-LD serialization
        # @return [Hash]
        def to_hash
          hash = { id: id, entity_type: entity_type }
          hash[:source_references] = source_references if source_references&.any?
          hash[:linked_entities] = linked_entities if linked_entities&.any?
          hash[:same_as] = same_as if same_as&.any?
          hash[:remarks] = remarks if remarks
          hash
        end

        # JSON mapping
        json do
          map :id, to: :id
          map :entity_type, to: :entity_type
          map :source_references, to: :source_references
          map :linked_entities, to: :linked_entities
          map :same_as, to: :same_as
          map :remarks, to: :remarks
        end

        # YAML mapping
        yaml do
          map :id, to: :id
          map :entity_type, to: :entity_type
          map :source_references, to: :source_references
          map :linked_entities, to: :linked_entities
          map :same_as, to: :same_as
          map :remarks, to: :remarks
        end
      end
    end
  end
end
