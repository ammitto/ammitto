# frozen_string_literal: true

require 'lutaml/model'
require_relative '../value_objects'

module Ammitto
  module Ontology
    module Sanction
      # Represents a status change in a sanction entry
      #
      # @example Creating a status history entry
      #   history = StatusHistory.new(
      #     status: :delisted,
      #     date: Date.new(2023, 5, 15),
      #     reason: "Delisted following court order"
      #   )
      #
      class StatusHistory < Lutaml::Model::Serializable
        # Status value
        # @return [Symbol, String]
        attribute :status, :string

        # Date of status change
        # @return [Date, nil]
        attribute :date, :date

        # Reason for status change
        # @return [String, nil]
        attribute :reason, :string

        # Convert to hash for JSON-LD serialization
        # @return [Hash]
        def to_hash
          hash = { status: status }
          hash[:date] = date.to_s if date
          hash[:reason] = reason if reason
          hash
        end

        # JSON mapping
        json do
          map :status, to: :status
          map :date, to: :date
          map :reason, to: :reason
        end

        # YAML mapping
        yaml do
          map :status, to: :status
          map :date, to: :date
          map :reason, to: :reason
        end
      end
    end
  end
end
