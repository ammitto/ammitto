# frozen_string_literal: true

require_relative 'entity'
require_relative 'address'
require_relative 'contact_info'
require_relative 'entity_link'
require_relative 'identification'
require_relative 'ontology/contracts'
require_relative 'ontology/entities/organization_entity'

module Ammitto
  # OrganizationEntity represents a sanctioned organization or company
  #
  # Legacy facade: its fields are projected from
  # Ontology::Entities::OrganizationEntity (see Ontology::Contracts). Here
  # +beneficial_owners+ are EntityLinks (canonical +beneficial_owner_links+);
  # the canonical name strings are +beneficial_owner_names+.
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
    Ontology::Contracts.declare_legacy_attributes(self)

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
      map 'organizationType', to: :organization_type
      map 'incorporationCountry', to: :incorporation_country
      map 'industry', to: :industry
      map 'beneficialOwnerNames', to: :beneficial_owner_names
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
