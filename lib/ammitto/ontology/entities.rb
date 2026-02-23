# frozen_string_literal: true

# Entity classes for the Ammitto Sanctions Ontology
#
# Entities are objects with unique identity. Each entity can have
# multiple sanction entries from different authorities.

require_relative 'entity'
require_relative 'person_entity'
require_relative 'organization_entity'
require_relative 'vessel_entity'
require_relative 'aircraft_entity'

module Ammitto
  module Ontology
    # Namespace for all entity classes
    module Entities
      # Factory method to create entity of appropriate type
      # @param entity_type [Symbol, String] type of entity
      # @param args [Hash] arguments for entity constructor
      # @return [Entity] appropriate entity subclass
      def self.create(entity_type, **args)
        case entity_type.to_sym
        when :person
          PersonEntity.new(**args)
        when :organization
          OrganizationEntity.new(**args)
        when :vessel
          VesselEntity.new(**args)
        when :aircraft
          AircraftEntity.new(**args)
        else
          raise ArgumentError, "Unknown entity type: #{entity_type}"
        end
      end
    end
  end
end
