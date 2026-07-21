# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Ontology
    module ValueObjects
      # HarmonizedName represents a name variant with provenance information
      # showing which sources contribute this name.
      #
      # @example
      #   name = HarmonizedName.new(
      #     full_name: "Aamir Ali Chaudhry",
      #     script: :Latn,
      #     is_primary: true,
      #     sources: [
      #       SourceProvenance.new(source_code: "uk", confidence: 0.95),
      #       SourceProvenance.new(source_code: "eu", confidence: 0.92)
      #     ]
      #   )
      #
      class HarmonizedName < Lutaml::Model::Serializable
        # Full name
        # @return [String]
        attribute :full_name, :string

        # Script (ISO 15924)
        # @return [Symbol, nil]
        attribute :script, :string

        # Whether this is the primary name
        # @return [Boolean]
        attribute :is_primary, :boolean, default: false

        # Sources that provide this name
        # @return [Array<SourceProvenance>]
        attribute :sources, SourceProvenance, collection: true

        # Custom setter for script
        def script=(value)
          super(value&.to_s)
        end

        # JSON mapping
        json do
          map :full_name, to: :full_name
          map :script, to: :script
          map :is_primary, to: :is_primary
          map :sources, to: :sources
        end

        # YAML mapping
        yaml do
          map :full_name, to: :full_name
          map :script, to: :script
          map :is_primary, to: :is_primary
          map :sources, to: :sources
        end
      end
    end
  end
end
