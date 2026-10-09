# frozen_string_literal: true

require 'date'

require_relative 'authority'
require_relative 'sanction_regime'
require_relative 'list_type'
require_relative 'sanction_effect'
require_relative 'sanction_reason'
require_relative 'temporal_period'
require_relative 'status_change'
require_relative 'legal_instrument'
require_relative 'official_announcement'
require_relative 'raw_source_data'
require_relative 'ontology/value_objects/legal_citation'
require_relative 'ontology/sanction/sanction_period_modification'

module Ammitto
  # SanctionEntry represents a single sanction entry
  #
  # This is the core unit of the data model. A SanctionEntry represents
  # the act of sanctioning an entity by a specific authority.
  #
  # One entity can have multiple sanction entries from different authorities.
  #
  # @example Creating a sanction entry
  #   SanctionEntry.new(
  #     id: "https://ammitto.org/entry/un/KPi.033",
  #     authority: Authority.find("un"),
  #     entity_id: "https://ammitto.org/entity/957a3b2c...",
  #     regime: SanctionRegime.new(name: "DPRK", code: "DPRK"),
  #     status: "active",
  #     reference_number: "KPi.033"
  #   )
  #
  class SanctionEntry < Lutaml::Model::Serializable
    # Sanction status values
    STATUSES = StatusChange::STATUSES

    attribute :id, :string                        # URI identifier
    attribute :entity_id, :string                 # Reference to Entity
    attribute :authority, Authority               # Issuing authority
    attribute :regime, SanctionRegime             # Sanctions regime
    attribute :list_type, ListType                # Type of list
    attribute :legal_bases, LegalInstrument, collection: true
    attribute :effects, SanctionEffect, collection: true
    attribute :reasons, SanctionReason, collection: true
    attribute :period, TemporalPeriod             # Time period
    attribute :status, :string, default: 'active' # Current status
    attribute :status_history, StatusChange, collection: true
    attribute :modifications, Ontology::Sanction::SanctionPeriodModification, collection: true
    attribute :reference_number, :string          # Authority's ID
    attribute :remarks, :string                   # Additional remarks
    attribute :announcement, OfficialAnnouncement # Official announcement
    attribute :group_id, :string                  # Reference to SanctionGroup
    attribute :legal_citations, Ontology::ValueObjects::LegalCitation, collection: true
    attribute :raw_source_data, RawSourceData     # Original source data

    json do
      map 'id', to: :id
      map 'entityId', to: :entity_id
      map 'authority', to: :authority
      map 'regime', to: :regime
      map 'listType', to: :list_type
      map 'legalBases', to: :legal_bases
      map 'effects', to: :effects
      map 'reasons', to: :reasons
      map 'period', to: :period
      map 'status', to: :status
      map 'statusHistory', to: :status_history
      map 'modifications', to: :modifications
      map 'referenceNumber', to: :reference_number
      map 'remarks', to: :remarks
      map 'announcement', to: :announcement
      map 'groupId', to: :group_id
      map 'legalCitations', to: :legal_citations
      map 'rawSourceData', to: :raw_source_data
    end

    # @return [Boolean] whether the sanction is currently active
    def active?
      status == 'active' && period&.active? != false
    end

    # @return [Boolean] whether the sanction is suspended
    def suspended?
      status == 'suspended'
    end

    # @return [Boolean] whether the sanction is terminated
    def terminated?
      %w[terminated delisted expired].include?(status)
    end

    # @return [String] the authority code
    def authority_code
      authority&.id
    end

    # @return [Array<String>] list of effect types
    def effect_types
      effects.map(&:effect_type).compact
    end

    # @return [Array<String>] list of reason categories
    def reason_categories
      reasons.map(&:category).compact
    end

    # Check if this entry matches a search term
    # @param term [String] the search term
    # @return [Boolean] whether there's a match
    def matches?(term)
      term_lower = term.downcase

      # Check reference number
      return true if reference_number&.downcase&.include?(term_lower)

      # Check regime
      return true if regime&.name&.downcase&.include?(term_lower)
      return true if regime&.code&.downcase&.include?(term_lower)

      # Check remarks
      return true if remarks&.downcase&.include?(term_lower)

      # Check reasons
      reasons.any? do |reason|
        reason.description&.downcase&.include?(term_lower) ||
          reason.category&.downcase&.include?(term_lower)
      end
    end

    # Get the most recent status change
    # @return [StatusChange, nil] the most recent status change
    def latest_status_change
      status_history.max_by(&:date)
    end

    # Keep historical status queries separate so current published status is not mutated.
    # @param date [Date, String, Time]
    # @return [String]
    def status_as_of(date)
      as_of = Date.parse(date.to_s)
      changes = Array(status_history).sort_by { |change| Date.parse(change.date.to_s) }
      # With no recorded history the current status is all there is to go on.
      return status || 'active' if changes.empty?

      # Before its first recorded change an entry was in force: the current
      # status describes the end of the history, not its start.
      status = changes.first&.from_status || 'active'

      changes.each do |change|
        change_date = Date.parse(change.date.to_s)
        break if change_date > as_of

        return 'terminated' if change.termination?

        status = change.to_status
        next unless change.suspension? && change.suspension_end_date

        status = 'active' if as_of > change.suspension_end_date
      end

      status
    end

    # Add a status change to history
    # @param change [StatusChange] the status change to add
    def add_status_change(change)
      @status_history ||= []
      @status_history << change
      @status_history.sort_by!(&:date)
      @status = change.to_status
    end
  end
end
