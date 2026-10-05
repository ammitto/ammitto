# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Ontology
    module ValueObjects
      # SourceEntityReference represents a link from a HarmonizedEntity
      # to a source-specific entity.
      #
      # This tracks the relationship between the canonical entity and
      # its appearances in different sanctions lists.
      #
      class SourceEntityReference < Lutaml::Model::Serializable
        # IRI of the source entity
        # @return [String]
        attribute :iri, :string

        # Source code (uk, eu, un, etc.)
        # @return [String]
        attribute :source_code, :string

        # Original entity type from source
        # @return [String]
        attribute :original_type, :string

        # Whether the original type matches the harmonized type
        # @return [Boolean]
        attribute :type_matches_harmonized, :boolean, default: true

        # Match confidence (0.0-1.0)
        # @return [Float]
        attribute :match_confidence, :float

        # JSON mapping
        json do
          map :iri, to: :iri
          map :source_code, to: :source_code
          map :original_type, to: :original_type
          map :type_matches_harmonized, to: :type_matches_harmonized
          map :match_confidence, to: :match_confidence
        end

        # YAML mapping
        yaml do
          map :iri, to: :iri
          map :source_code, to: :source_code
          map :original_type, to: :original_type
          map :type_matches_harmonized, to: :type_matches_harmonized
          map :match_confidence, to: :match_confidence
        end
      end
    end
  end
end
