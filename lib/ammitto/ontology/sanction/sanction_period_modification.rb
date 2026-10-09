# frozen_string_literal: true

require 'lutaml/model'
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
      # @example Creating a suspension
      #   mod = SanctionPeriodModification.new(
      #     id: "https://www.ammitto.org/modification/cn/2025-001",
      #     target_type: "announcement",
      #     target_announcement_id: "https://www.ammitto.org/announcement/cn/2024-015",
      #     target_announcement_document_id: "〔2025〕7号",
      #     target_announcement_date: Date.new(2024, 12, 15),
      #     effective_date: Date.new(2025, 1, 1),
      #     until_date: Date.new(2025, 4, 1),
      #     action: "suspend",
      #     notes: "暂停相关措施90天"
      #   )
      #
      # @example Creating a delisting (stop action)
      #   mod = SanctionPeriodModification.new(
      #     target_type: "announcement",
      #     action: "stop",
      #     effective_date: Date.new(2025, 2, 15),
      #     announcement: { 'id' => 'https://www.ammitto.org/announcement/cn/2025-015' }
      #   )
      #
      class SanctionPeriodModification < Lutaml::Model::Serializable
        # Unique IRI identifier
        # @return [String, nil]
        attribute :id, :string

        # Type of target being modified (entry, group, list)
        # @return [String, nil]
        attribute :target_type, :string

        # IRIs of affected sanction entries
        # @return [Array<String>, nil]
        attribute :target_id, :string, collection: true

        # Announcement that originally created the target
        # @return [String, nil]
        attribute :target_announcement_id, :string

        # Source document number, retained separately from its minted IRI
        # @return [String, nil]
        attribute :target_announcement_document_id, :string

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

        # Announcement that triggered this modification. A hash keeps this
        # model independent from OfficialAnnouncement's reverse reference.
        # @return [Hash, nil]
        attribute :announcement, :hash

        # Legal citations for this modification
        # @return [Array<LegalCitation>, nil]
        attribute :legal_citations, ValueObjects::LegalCitation, collection: true

        # Additional notes
        # @return [String, nil]
        attribute :notes, :string

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
          map :target_announcement_document_id, to: :target_announcement_document_id
          map :target_announcement_date, to: :target_announcement_date
          map :affected_entity_count, to: :affected_entity_count
          map :affected_entity_names, to: :affected_entity_names
          map :action, to: :action
          map :effective_date, to: :effective_date
          map :effective_time, to: :effective_time
          map :until_date, to: :until_date
          map :until_time, to: :until_time
          map :announcement, to: :announcement
          map :legal_citations, to: :legal_citations
          map :notes, to: :notes
        end

        json do
          map 'id', to: :id
          map 'targetType', to: :target_type
          map 'targetId', to: :target_id
          map 'targetAnnouncementId', to: :target_announcement_id
          map 'targetAnnouncementDocumentId', to: :target_announcement_document_id
          map 'targetAnnouncementDate', to: :target_announcement_date
          map 'action', to: :action
          map 'effectiveDate', to: :effective_date
          map 'effectiveTime', to: :effective_time
          map 'untilDate', to: :until_date
          map 'untilTime', to: :until_time
          map 'announcement', to: :announcement
          map 'affectedEntityCount', to: :affected_entity_count
          map 'affectedEntityNames', to: :affected_entity_names
          map 'legalCitations', to: :legal_citations
          map 'notes', to: :notes
        end
      end
    end
  end
end
