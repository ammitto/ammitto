# frozen_string_literal: true

module Ammitto
  # OrganizationEntity represents a sanctioned organization or company
  #
  # @example Creating an organization entity
  #   OrganizationEntity.new(
  #     id: "https://ammitto.org/entity/456",
  #     names: [NameVariant.new(full_name: "ACME Corp", is_primary: true)],
  #     registration_number: "12345678",
  #     country: "United States"
  #   )
  #
  class OrganizationEntity < Entity
    attribute :entity_type, :string, default: 'organization'
    attribute :registration_number, :string
    attribute :incorporation_date, :date
    attribute :dissolution_date, :date
    attribute :legal_form, :string            # Corporation, LLC, Partnership, etc.
    attribute :country, :string               # Country of incorporation
    attribute :country_iso_code, :string      # ISO 3166-1 alpha-2
    attribute :identifications, Identification, collection: true
    attribute :addresses, Address, collection: true
    attribute :contact_info, ContactInfo
    attribute :beneficial_owners, EntityLink, collection: true
    attribute :directors, EntityLink, collection: true
    attribute :parent_organization, EntityLink
    attribute :subsidiaries, EntityLink, collection: true
    attribute :website, :string
    attribute :sector, :string                # Industry sector

    json do
      map 'entityType', to: :entity_type
      map 'registrationNumber', to: :registration_number
      map 'incorporationDate', to: :incorporation_date
      map 'dissolutionDate', to: :dissolution_date
      map 'legalForm', to: :legal_form
      map 'country', to: :country
      map 'countryIsoCode', to: :country_iso_code
      map 'identifications', to: :identifications
      map 'addresses', to: :addresses
      map 'contactInfo', to: :contact_info
      map 'beneficialOwners', to: :beneficial_owners
      map 'directors', to: :directors
      map 'parentOrganization', to: :parent_organization
      map 'subsidiaries', to: :subsidiaries
      map 'website', to: :website
      map 'sector', to: :sector
    end

    # @return [Boolean] whether the organization is dissolved
    def dissolved?
      !dissolution_date.nil?
    end

    # Check if this organization matches a search term
    # @param term [String] the search term
    # @return [Boolean] whether there's a match
    def matches?(term)
      return true if super

      term_lower = term.downcase

      # Check registration number
      return true if registration_number&.downcase&.include?(term_lower)

      # Check country
      return true if country&.downcase&.include?(term_lower)

      # Check website
      return true if website&.downcase&.include?(term_lower)

      # Check sector
      return true if sector&.downcase&.include?(term_lower)

      # Check identifications
      identifications.any? do |id|
        id.number&.downcase&.include?(term_lower)
      end
    end
  end
end
