# frozen_string_literal: true

require 'lutaml/model'
require_relative '../value_objects/localized_string'
require_relative '../value_objects/legal_citation'

module Ammitto
  module Ontology
    module Sanction
      # Represents a temporal modification to sanctions
      #
      # SanctionPeriodModification records changes to sanctions over time,
      # such as suspensions, resumptions, terminations, amendments, or extensions.
      # It provides a structured way to track the history of changes.
      #
      # @example Creating a 90-day suspension
      #   mod = SanctionPeriodModification.new(
      #     id: "https://www.ammitto.org/modification/cn/2025-001",
      #     target_type: "entry",
      #     target_id: "https://www.ammitto.org/entry/cn/uel-2024-015",
      #     target_announcement_id: "https://www.ammitto.org/announcement/cn/2024-015",
      #     target_announcement_date: Date.new(2024, 12, 15),
      #     action: "suspend",
      #     effective_date: Date.new(2025, 1, 1),
      #     until_date: Date.new(2025, 4, 1),
      #     duration_days: 90,
      #     duration_description: "90天",
      #     announcement_id: "https://www.ammitto.org/announcement/cn/2025-001",
      #     status: "active"
      #   )
      #
      # @example Creating a delisting (stop action)
      #   mod = SanctionPeriodModification.new(
      #     target_type: "entry",
      #     target_id: "https://www.ammitto.org/entry/cn/uel-2024-020",
      #     action: "stop",
      #     effective_date: Date.new(2025, 2, 15),
      #     announcement_id: "https://www.ammitto.org/announcement/cn/2025-015"
      #   )
      #
      class SanctionPeriodModification < Lutaml::Model::Serializable
        # Unique IRI identifier
        # @return [String, nil]
        attribute :id, :string

        # Type of target being modified (entry, group, list)
        # @return [String, nil]
        attribute :target_type, :string

        # IRI of the target being modified
        # @return [String, nil]
        attribute :target_id, :string

        # Announcement that originally created the target
        # @return [String, nil]
        attribute :target_announcement_id, :string

        # Date of the original announcement
        # @return [Date, nil]
        attribute :target_announcement_date, :date

        # Number of entities affected
        # @return [Integer, nil]
        attribute :affected_entity_count, :integer

        # Names of affected entities
        # @return [Array<String>, nil]
        attribute :affected_entity_names, :string, collection: true

        # Modification action (suspend, resume, stop, amend, extend)
        # @return [String, nil]
        attribute :action, :string

        # Date when the modification becomes effective
        # @return [Date, nil]
        attribute :effective_date, :date

        # Time when the modification becomes effective
        # @return [String, nil]
        attribute :effective_time, :string

        # End date for suspension (for suspend/resume actions)
        # @return [Date, nil]
        attribute :until_date, :date

        # End time for suspension
        # @return [String, nil]
        attribute :until_time, :string

        # Duration in days
        # @return [Integer, nil]
        attribute :duration_days, :integer

        # Duration description in original language (e.g., "90天", "1年")
        # @return [String, nil]
        attribute :duration_description, :string

        # Announcement that triggered this modification
        # @return [String, nil]
        attribute :announcement_id, :string

        # Legal citations for this modification
        # @return [Array<LegalCitation>, nil]
        attribute :legal_citations, ValueObjects::LegalCitation, collection: true

        # Reason for the modification (multilingual)
        # @return [Array<LocalizedString>, nil]
        attribute :reason, ValueObjects::LocalizedString, collection: true

        # Additional notes
        # @return [String, nil]
        attribute :notes, :string

        # Current status (active, expired, superseded)
        # @return [String]
        attribute :status, :string, default: 'active'

        # Check if this is a suspension
        # @return [Boolean]
        def suspension?
          action == 'suspend'
        end

        # Check if this is a delisting
        # @return [Boolean]
        def delisting?
          action == 'stop'
        end

        # Check if modification is active
        # @return [Boolean]
        def active?
          status == 'active'
        end

        # Check if suspension has expired
        # @return [Boolean]
        def expired?
          return false unless suspension?
          return false unless until_date

          until_date < Date.today
        end

        # Get the effective datetime
        # @return [String, nil]
        def effective_datetime
          return nil unless effective_date

          time = effective_time || '00:00'
          "#{effective_date}T#{time}:00"
        end

        # Get the until datetime
        # @return [String, nil]
        def until_datetime
          return nil unless until_date

          time = until_time || '23:59'
          "#{until_date}T#{time}:00"
        end

        # Check if this modification affects multiple entities
        # @return [Boolean]
        def batch?
          !affected_entity_count.nil? && affected_entity_count > 1
        end

        key_value do
          map :id, to: :id
          map :target_type, to: :target_type
          map :target_id, to: :target_id
          map :target_announcement_id, to: :target_announcement_id
          map :target_announcement_date, to: :target_announcement_date
          map :affected_entity_count, to: :affected_entity_count
          map :affected_entity_names, to: :affected_entity_names
          map :action, to: :action
          map :effective_date, to: :effective_date
          map :effective_time, to: :effective_time
          map :until_date, to: :until_date
          map :until_time, to: :until_time
          map :duration_days, to: :duration_days
          map :duration_description, to: :duration_description
          map :announcement_id, to: :announcement_id
          map :legal_citations, to: :legal_citations
          map :reason, to: :reason
          map :notes, to: :notes
          map :status, to: :status
        end
      end
    end
  end
end
