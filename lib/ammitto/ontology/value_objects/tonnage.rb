# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Ontology
    module ValueObjects
      # Tonnage represents vessel tonnage measurements
      #
      # Tonnage values are used to describe vessel capacity and size
      # using various international standards.
      #
      # @example Creating tonnage info
      #   Tonnage.new(
      #     gt: 5000,
      #     dwt: 8000,
      #     nt: 3500
      #   )
      #
      class Tonnage < Lutaml::Model::Serializable
        # Gross Tonnage (GT) - modern measurement
        # @return [Integer, nil]
        attribute :gt, :integer

        # Deadweight Tonnage (DWT) - carrying capacity
        # @return [Integer, nil]
        attribute :dwt, :integer

        # Net Tonnage (NT) - cargo space
        # @return [Integer, nil]
        attribute :nt, :integer

        # Gross Register Tonnage (GRT) - legacy measurement
        # @return [Integer, nil]
        attribute :grt, :integer

        # @return [Boolean] whether any tonnage is present
        def present?
          [gt, dwt, nt, grt].any? { |v| v&.positive? }
        end

        # Convert to hash for JSON-LD serialization
        # @return [Hash]
        def to_hash
          hash = {}
          hash[:gt] = gt if gt
          hash[:dwt] = dwt if dwt
          hash[:nt] = nt if nt
          hash[:grt] = grt if grt
          hash
        end

        # JSON mapping
        json do
          map 'gt', to: :gt
          map 'dwt', to: :dwt
          map 'nt', to: :nt
          map 'grt', to: :grt
        end

        # YAML mapping
        yaml do
          map 'gt', to: :gt
          map 'dwt', to: :dwt
          map 'nt', to: :nt
          map 'grt', to: :grt
        end
      end
    end
  end
end
