# frozen_string_literal: true

require 'lutaml/model'
require_relative 'sanction_reason'
require_relative '../value_objects/temporal_period'
require_relative '../value_objects/sanction_effect'

module Ammitto
  module Ontology
    module Sanction
      # Represents a collection of sanction entries announced together
      #
      # SanctionGroup groups entries that were announced together in a single
      # official announcement. This is important because an announcement may
      # sanction multiple entities with identical measures, and provides context
      # for understanding collective sanctions.
      #
      # @example Creating a sanction group from an announcement
      #   group = SanctionGroup.new(
      #     id: "https://www.ammitto.org/group/cn/2025-01-02-uel",
      #     announcement_id: "https://www.ammitto.org/announcement/cn/2025-01-02",
      #     list_id: "https://www.ammitto.org/list/cn/UEL",
      #     entry_ids: [
      #       "https://www.ammitto.org/entry/cn/uel-2025-001",
      #       "https://www.ammitto.org/entry/cn/uel-2025-002"
      #     ],
      #     entity_count: 2,
      #     effective_date: Date.new(2025, 1, 2)
      #   )
      #
      class SanctionGroup < Lutaml::Model::Serializable
        # Unique IRI identifier
        # @return [String, nil]
        attribute :id, :string

        # Reference to the OfficialAnnouncement
        # @return [String, nil]
        attribute :announcement_id, :string

        # Title of the announcement this group is from
        # @return [String, nil]
        attribute :announcement_title, :string

        # Reference to the SanctionList this group belongs to
        # @return [String, nil]
        attribute :list_id, :string

        # IDs of SanctionEntry objects in this group
        # @return [Array<String>, nil]
        attribute :entry_ids, :string, collection: true

        # Shared measures applied to all entries in this group
        # @return [Array<ValueObjects::SanctionEffect>, nil]
        attribute :shared_measures, ValueObjects::SanctionEffect, collection: true

        # Shared reasons for all entries in this group
        # @return [Array<SanctionReason>, nil]
        attribute :shared_reasons, SanctionReason, collection: true

        # Date when the sanctions become effective
        # @return [Date, nil]
        attribute :effective_date, :date

        # Time when the sanctions become effective (e.g., "00:00")
        # @return [String, nil]
        attribute :effective_time, :string

        # Number of entities in this group
        # @return [Integer, nil]
        attribute :entity_count, :integer

        # Additional notes about the group
        # @return [String, nil]
        attribute :notes, :string

        # Check if group has shared measures
        # @return [Boolean]
        def shared_measures?
          shared_measures&.any? || false
        end

        # Check if group has shared reasons
        # @return [Boolean]
        def shared_reasons?
          shared_reasons&.any? || false
        end

        # Get the effective datetime (date + time)
        # @return [String, nil] ISO 8601 datetime string
        def effective_datetime
          return nil unless effective_date

          time = effective_time || '00:00'
          "#{effective_date}T#{time}:00"
        end

        key_value do
          map :id, to: :id
          map :announcement_id, to: :announcement_id
          map :announcement_title, to: :announcement_title
          map :list_id, to: :list_id
          map :entry_ids, to: :entry_ids
          map :shared_measures, to: :shared_measures
          map :shared_reasons, to: :shared_reasons
          map :effective_date, to: :effective_date
          map :effective_time, to: :effective_time
          map :entity_count, to: :entity_count
          map :notes, to: :notes
        end
      end
    end
  end
end
