# frozen_string_literal: true

require 'lutaml/model'
require_relative '../types'
require_relative 'authority'
require_relative 'sanction_regime'
require_relative 'sanction_period_modification'
require_relative 'status_history'
require_relative '../value_objects'
require_relative '../value_objects/legal_citation'

module Ammitto
  module Ontology
    module Sanction
      # Represents a sanction entry linking an entity to a sanction
      #
      # A SanctionEntry represents the imposition of sanctions on an
      # entity by an authority under a specific regime. It includes
      # information about the legal basis, effects, and time period.
      #
      # @example Creating a sanction entry
      #   entry = SanctionEntry.new(
      #     id: "https://www.ammitto.org/entry/eu/EU.123.45",
      #     entity_id: "https://www.ammitto.org/entity/eu/EU.123.45",
      #     authority: Authority.new(id: "eu", name: "European Union"),
      #     regime: SanctionRegime.new(code: "RUS", name: "Russia/Ukraine"),
      #     effects: [SanctionEffect.new(effect_type: "asset_freeze", scope: "full")],
      #     status: :active
      #   )
      #
      class SanctionEntry < Lutaml::Model::Serializable
        # Unique URI identifier for this entry
        # @return [String]
        attribute :id, :string

        # URI of the sanctioned entity
        # @return [String]
        attribute :entity_id, :string

        # Authority that imposed the sanction
        # @return [Authority]
        attribute :authority, Authority

        # Sanction regime/programme
        # @return [SanctionRegime, nil]
        attribute :regime, SanctionRegime

        # Type of list (consolidated, sectoral, etc.)
        # @return [String, nil]
        attribute :list_type, :string

        # Legal instruments (regulations, laws) as basis
        # @return [Array<LegalInstrument>, nil]
        attribute :legal_bases, ValueObjects::LegalInstrument, collection: true

        # Sanction effects/restrictions
        # @return [Array<SanctionEffect>]
        attribute :effects, ValueObjects::SanctionEffect, collection: true

        # Reasons for sanction (free text)
        # @return [Array<String>, nil]
        attribute :reasons, :string, collection: true

        # Temporal period (listing/effective/expiry dates)
        # @return [TemporalPeriod, nil]
        attribute :period, ValueObjects::TemporalPeriod

        # Current status
        # @return [Symbol, String]
        attribute :status, :string, default: 'active'

        # History of status changes
        # @return [Array<StatusHistory>, nil]
        attribute :status_history, StatusHistory, collection: true

        # Official reference number from source
        # @return [String, nil]
        attribute :reference_number, :string

        # Remarks
        # @return [String, nil]
        attribute :remarks, :string

        # Announcement information
        # @return [String, nil]
        attribute :announcement, :string

        # Raw source data reference
        # @return [RawSourceData, nil]
        attribute :raw_source_data, :hash

        # Reference to SanctionGroup (if part of collective sanction)
        # @return [String, nil]
        attribute :group_id, :string

        # Modifications affecting this entry
        # @return [Array<SanctionPeriodModification>, nil]
        attribute :modifications, SanctionPeriodModification, collection: true

        # Legal citations (specific to this entry)
        # @return [Array<LegalCitation>, nil]
        attribute :legal_citations, ValueObjects::LegalCitation, collection: true

        # Check if entry is active
        # @return [Boolean]
        def active?
          status == 'active'
        end

        # Check if entry is delisted
        # @return [Boolean]
        def delisted?
          status == 'delisted'
        end

        # Get status as symbol
        # @return [Symbol]
        def status_sym
          status&.to_sym
        end

        # Add a status change to history
        # @param new_status [Symbol, String] one of Types::SANCTION_STATUSES
        # @param date [Date]
        # @param reason [String, nil]
        # @return [void]
        # @raise [ArgumentError] when new_status is blank or not a known
        #   sanction status
        def add_status_change(new_status, date: Date.today, reason: nil)
          normalized = new_status.to_s.downcase
          unless Types.valid_status?(normalized)
            raise ArgumentError,
                  "invalid sanction status: #{new_status.inspect}"
          end

          self.status_history ||= []
          status_history << StatusHistory.new(
            from_status: status,
            to_status: normalized,
            date: date,
            reason: reason
          )
          self.status = normalized
        end

        key_value do
          map :id, to: :id
          map :entity_id, to: :entity_id
          map :authority, to: :authority
          map :regime, to: :regime
          map :list_type, to: :list_type
          map :legal_bases, to: :legal_bases
          map :effects, to: :effects
          map :reasons, to: :reasons
          map :period, to: :period
          map :status, to: :status
          map :status_history, to: :status_history
          map :reference_number, to: :reference_number
          map :remarks, to: :remarks
          map :announcement, to: :announcement
          map :raw_source_data, to: :raw_source_data
          map :group_id, to: :group_id
          map :modifications, to: :modifications
          map :legal_citations, to: :legal_citations
        end
      end
    end
  end
end
