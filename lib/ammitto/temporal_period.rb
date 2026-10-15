# frozen_string_literal: true

require_relative 'ontology/contracts'
require_relative 'ontology/value_objects/temporal_period'

module Ammitto
  # TemporalPeriod represents the time period of a sanction
  #
  # Documents when a sanction was listed, effective, and when it expires.
  #
  # Legacy facade: its fields are projected from
  # Ontology::ValueObjects::TemporalPeriod (see Ontology::Contracts).
  # Here +last_updated+ is the raw ISO 8601 timestamp (canonical
  # +last_updated_timestamp+); the canonical Date is +last_updated_date+.
  #
  # @example Creating a temporal period
  #   TemporalPeriod.new(
  #     listed_date: "2016-11-30",
  #     effective_date: "2016-11-30",
  #     is_indefinite: true
  #   )
  #
  class TemporalPeriod < Lutaml::Model::Serializable
    Ontology::Contracts.declare_legacy_attributes(self)

    json do
      map 'listedDate', to: :listed_date
      map 'listedTime', to: :listed_time
      map 'effectiveDate', to: :effective_date
      map 'effectiveTime', to: :effective_time
      map 'expiryDate', to: :expiry_date
      map 'isIndefinite', to: :is_indefinite
      map 'lastUpdated', to: :last_updated
      map 'lastUpdatedDate', to: :last_updated_date
    end

    # @return [Boolean] whether the sanction is currently active
    def active?
      return false if expiry_date && expiry_date < Date.today

      true
    end

    # @return [Integer, nil] number of days until expiry
    def days_until_expiry
      return nil unless expiry_date

      (expiry_date - Date.today).to_i
    end

    # @return [String] formatted duration string
    def duration
      return 'Indefinite' if is_indefinite

      parts = []
      parts << "Listed: #{listed_date}" if listed_date
      parts << "Effective: #{effective_date}" if effective_date
      parts << "Expires: #{expiry_date}" if expiry_date
      parts.join('; ')
    end
  end
end
