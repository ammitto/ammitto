# frozen_string_literal: true

module Ammitto
  # TemporalPeriod represents the time period of a sanction
  #
  # Documents when a sanction was listed, effective, and when it expires.
  #
  # @example Creating a temporal period
  #   TemporalPeriod.new(
  #     listed_date: "2016-11-30",
  #     effective_date: "2016-11-30",
  #     is_indefinite: true
  #   )
  #
  class TemporalPeriod < Lutaml::Model::Serializable
    attribute :listed_date, :date      # Date entity was listed
    attribute :effective_date, :date   # Date sanction became effective
    attribute :expiry_date, :date      # Date sanction expires (if applicable)
    attribute :is_indefinite, :boolean, default: false
    attribute :last_updated, :string # Last update timestamp (ISO 8601)

    json do
      map 'listedDate', to: :listed_date
      map 'effectiveDate', to: :effective_date
      map 'expiryDate', to: :expiry_date
      map 'isIndefinite', to: :is_indefinite
      map 'lastUpdated', to: :last_updated
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
