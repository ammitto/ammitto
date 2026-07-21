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
        # Previous status (for transitions)
        # @return [String, nil]
        attribute :from_status, :string

        # New status value
        # @return [String]
        attribute :to_status, :string

        # Legacy attribute - maps to to_status
        # @return [String]
        attribute :status, :string

        # Date of status change
        # @return [Date, nil]
        attribute :date, :date

        # Reason for status change
        # @return [String, nil]
        attribute :reason, :string

        # End date if status is suspended
        # @return [Date, nil]
        attribute :suspension_end_date, :date

        def initialize(*args)
          super
          # Ensure to_status is set from status if not explicitly provided
          self.to_status ||= status
        end

        # Convert to hash for JSON-LD serialization
        # @return [Hash]
        def to_hash
          hash = {}
          hash[:from_status] = from_status if from_status
          hash[:to_status] = to_status || status
          hash[:date] = date.to_s if date
          hash[:reason] = reason if reason
          hash[:suspension_end_date] = suspension_end_date.to_s if suspension_end_date
          hash
        end

        # JSON mapping
        json do
          map 'fromStatus', to: :from_status
          map 'toStatus', to: :to_status
          map 'status', to: :status
          map 'date', to: :date
          map 'reason', to: :reason
          map 'suspensionEndDate', to: :suspension_end_date
        end

        # YAML mapping
        yaml do
          map 'from_status', to: :from_status
          map 'to_status', to: :to_status
          map 'status', to: :status
          map 'date', to: :date
          map 'reason', to: :reason
          map 'suspension_end_date', to: :suspension_end_date
        end
      end
    end
  end
end
