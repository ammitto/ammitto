# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Ontology
    module Sanction
      # Represents a sanctions regime/programme
      #
      # Sanctions are organized into regimes based on geographic
      # or thematic focus (e.g., "Russia/Ukraine", "Iran", "DPRK").
      #
      # @example Creating a sanction regime
      #   regime = SanctionRegime.new(
      #     code: "RUS",
      #     name: "Russia/Ukraine",
      #     description: "Restrictive measures in respect of actions..."
      #   )
      #
      class SanctionRegime < Lutaml::Model::Serializable
        # Regime code (short identifier)
        # @return [String]
        attribute :code, :string

        # Full name of the regime
        # @return [String]
        attribute :name, :string

        # Description of the regime
        # @return [String, nil]
        attribute :description, :string

        # Convert to hash for JSON-LD serialization
        # @return [Hash]
        def to_hash
          hash = { code: code }
          hash[:name] = name if name
          hash[:description] = description if description
          hash
        end

        # JSON mapping
        json do
          map :code, to: :code
          map :name, to: :name
          map :description, to: :description
        end

        # YAML mapping
        yaml do
          map :code, to: :code
          map :name, to: :name
          map :description, to: :description
        end
      end
    end
  end
end
