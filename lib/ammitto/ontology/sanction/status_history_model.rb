# frozen_string_literal: true

require 'lutaml/model'
require_relative '../value_objects/immutable'
require_relative '../value_objects'
require_relative '../value_objects/notice_reference'

module Ammitto
  module Ontology
    module Sanction
      # Represents a status change in a sanction entry
      #
      # @example Recording a status transition
      #   history = StatusHistory.new(
      #     from_status: 'active',
      #     to_status: 'delisted',
      #     date: Date.new(2023, 5, 15),
      #     reason: "Delisted following court order"
      #   )
      #
      class StatusHistoryModel < Lutaml::Model::Serializable
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

        # When the change happened, exactly as the source wrote it (ISO
        # 8601, time and zone included); date cannot hold the time
        # @return [String, nil]
        attribute :timestamp, :string

        # Reason for status change
        # @return [String, nil]
        attribute :reason, :string

        # The official notice that made the change
        # @return [ValueObjects::NoticeReference, nil]
        attribute :notice_reference, ValueObjects::NoticeReference

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
          hash[:timestamp] = timestamp if timestamp
          hash[:reason] = reason if reason
          hash[:notice_reference] = notice_reference.to_hash if notice_reference
          hash[:suspension_end_date] = suspension_end_date.to_s if suspension_end_date
          hash
        end

        # JSON mapping
        json do
          map 'fromStatus', to: :from_status
          map 'toStatus', to: :to_status
          map 'status', to: :status
          map 'date', to: :date
          map 'timestamp', to: :timestamp
          map 'reason', to: :reason
          map 'noticeReference', to: :notice_reference
          map 'suspensionEndDate', to: :suspension_end_date
        end

        # YAML mapping
        yaml do
          map 'from_status', to: :from_status
          map 'to_status', to: :to_status
          map 'status', to: :status
          map 'date', to: :date
          map 'timestamp', to: :timestamp
          map 'reason', to: :reason
          map 'notice_reference', to: :notice_reference
          map 'suspension_end_date', to: :suspension_end_date
        end
      end
      private_constant :StatusHistoryModel
    end
  end
end
