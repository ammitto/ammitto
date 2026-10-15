# frozen_string_literal: true

require_relative 'ontology/contracts'
require_relative 'ontology/value_objects/identification'

module Ammitto
  # Identification represents an identification document
  #
  # Used for passports, national IDs, tax IDs, and other identity documents.
  #
  # Legacy facade: its fields are projected from
  # Ontology::ValueObjects::Identification (see Ontology::Contracts).
  #
  # @example Creating an identification
  #   Identification.new(
  #     type: "Passport",
  #     number: "381310014",
  #     issuing_country: "Jordan"
  #   )
  #
  class Identification < Lutaml::Model::Serializable
    # Common identification types
    TYPES = %w[
      Passport
      NationalID
      TaxID
      DriversLicense
      SocialSecurity
      SeafarerID
      MilitaryID
      DiplomaticPassport
      RefugeeID
      Other
    ].freeze

    Ontology::Contracts.declare_legacy_attributes(self)

    json do
      map 'type', to: :type
      map 'number', to: :number
      map 'issuingCountry', to: :issuing_country
      map 'countryIsoCode', to: :country_iso_code
      map 'issueDate', to: :issue_date
      map 'expiryDate', to: :expiry_date
      map 'note', to: :note
    end

    # @return [Boolean] whether the identification is expired
    def expired?
      return false unless expiry_date

      expiry_date < Date.today
    end

    # @return [String] formatted identification string
    def to_s
      parts = [type, number, issuing_country].compact
      parts.reject(&:empty?).join(' ')
    end
  end
end
