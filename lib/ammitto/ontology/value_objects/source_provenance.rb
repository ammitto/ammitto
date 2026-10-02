# frozen_string_literal: true

require 'lutaml/model'
# Callers that require only this file get SourceEntityReference with it.
require_relative 'source_entity_reference'

module Ammitto
  module Ontology
    module ValueObjects
      # SourceProvenance tracks which source contributed a piece of data
      # and the confidence of the match.
      #
      # @example
      #   provenance = SourceProvenance.new(
      #     source_code: "uk",
      #     source_entity_iri: "https://www.ammitto.org/entity/uk/xxx",
      #     match_confidence: 0.95,
      #     contributed_at: Time.now
      #   )
      #
      class SourceProvenance < Lutaml::Model::Serializable
        # Source code (uk, eu, un, etc.)
        # @return [String]
        attribute :source_code, :string

        # IRI of the source entity that contributed this data
        # @return [String, nil]
        attribute :source_entity_iri, :string

        # Confidence of the match (0.0-1.0)
        # @return [Float]
        attribute :match_confidence, :float

        # When this data was contributed
        # @return [DateTime, nil]
        attribute :contributed_at, :date_time

        # JSON mapping
        json do
          map :source_code, to: :source_code
          map :source_entity_iri, to: :source_entity_iri
          map :match_confidence, to: :match_confidence
          map :contributed_at, to: :contributed_at
        end

        # YAML mapping
        yaml do
          map :source_code, to: :source_code
          map :source_entity_iri, to: :source_entity_iri
          map :match_confidence, to: :match_confidence
          map :contributed_at, to: :contributed_at
        end
      end
    end
  end
end
