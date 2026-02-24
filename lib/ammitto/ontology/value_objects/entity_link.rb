# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Ontology
    module ValueObjects
      # EntityLink represents a relationship between entities
      #
      # Used to link entities to related organizations, beneficial owners,
      # vessels, aircraft, etc.
      #
      # @example Creating an entity link
      #   EntityLink.new(
      #     target_id: "https://ammitto.org/entity/abc123",
      #     relationship_type: "owned_by",
      #     target_name: "ABC Corp"
      #   )
      #
      class EntityLink < Lutaml::Model::Serializable
        # Common relationship types
        RELATIONSHIPS = %w[
          owned_by
          operated_by
          controlled_by
          beneficial_owner_of
          subsidiary_of
          parent_of
          affiliated_with
          related_to
          representative_of
          director_of
          officer_of
          shareholder_of
        ].freeze

        # URI of the target entity
        # @return [String, nil]
        attribute :target_id, :string

        # Type of relationship
        # @return [String, nil]
        attribute :relationship_type, :string

        # Name of target (for display)
        # @return [String, nil]
        attribute :target_name, :string

        # Entity type of target
        # @return [String, nil]
        attribute :target_type, :string

        # Source that provided this link
        # @return [String, nil]
        attribute :source, :string

        # Relationship start date
        # @return [Date, nil]
        attribute :from_date, :date

        # Relationship end date
        # @return [Date, nil]
        attribute :to_date, :date

        # Additional notes
        # @return [String, nil]
        attribute :note, :string

        # @return [Boolean] whether the relationship is current
        def current?
          return false if to_date && to_date < Date.today

          true
        end

        # Convert to hash for JSON-LD serialization
        # @return [Hash]
        def to_hash
          hash = {}
          hash[:target_id] = target_id if target_id
          hash[:relationship_type] = relationship_type if relationship_type
          hash[:target_name] = target_name if target_name
          hash[:target_type] = target_type if target_type
          hash[:source] = source if source
          hash[:from_date] = from_date.to_s if from_date
          hash[:to_date] = to_date.to_s if to_date
          hash[:note] = note if note
          hash
        end

        # JSON mapping
        json do
          map 'targetId', to: :target_id
          map 'relationshipType', to: :relationship_type
          map 'targetName', to: :target_name
          map 'targetType', to: :target_type
          map 'source', to: :source
          map 'fromDate', to: :from_date
          map 'toDate', to: :to_date
          map 'note', to: :note
        end

        # YAML mapping
        yaml do
          map 'target_id', to: :target_id
          map 'relationship_type', to: :relationship_type
          map 'target_name', to: :target_name
          map 'target_type', to: :target_type
          map 'source', to: :source
          map 'from_date', to: :from_date
          map 'to_date', to: :to_date
          map 'note', to: :note
        end
      end
    end
  end
end
