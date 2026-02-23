# frozen_string_literal: true

require_relative 'entity'

module Ammitto
  module Ontology
    module Entities
      # Represents an organization (company, group, etc.) subject to sanctions
      #
      # OrganizationEntity extends Entity with organization-specific attributes
      # such as registration numbers, addresses, and business information.
      #
      # @example Creating an organization entity
      #   org = OrganizationEntity.new(
      #     id: "https://www.ammitto.org/entity/eu/EU.456.78",
      #     names: [NameVariant.new(full_name: "Example Corp", is_primary: true)],
      #     addresses: [Address.new(city: "Moscow", country: "Russia")],
      #     registration_number: "12345678",
      #     incorporation_country: "RU"
      #   )
      #
      class OrganizationEntity < Entity
        # Name variants for this organization
        # @return [Array<NameVariant>]
        attribute :names, ValueObjects::NameVariant, collection: true

        # Addresses (registered, business, etc.)
        # @return [Array<Address>, nil]
        attribute :addresses, ValueObjects::Address, collection: true

        # Identification documents (registration, tax ID, etc.)
        # @return [Array<Identification>, nil]
        attribute :identifications, ValueObjects::Identification, collection: true

        # Contact information
        # @return [ContactInfo, nil]
        attribute :contact_info, ValueObjects::ContactInfo

        # Company/organization type (LLC, JSC, etc.)
        # @return [String, nil]
        attribute :organization_type, :string

        # Registration number
        # @return [String, nil]
        attribute :registration_number, :string

        # Country of incorporation
        # @return [String, nil]
        attribute :incorporation_country, :string

        # Date of incorporation
        # @return [Date, nil]
        attribute :incorporation_date, :date

        # Industry/sector
        # @return [String, nil]
        attribute :industry, :string

        # Website
        # @return [String, nil]
        attribute :website, :string

        def initialize(*args)
          super
          self.entity_type = 'organization'
        end

        # Get primary name
        # @return [String, nil]
        def primary_name
          primary = names&.find(&:primary?)
          primary&.full_name || names&.first&.full_name
        end

        # Get all name variants as strings
        # @return [Array<String>]
        def all_names
          names&.map(&:full_name)&.compact || []
        end

        # Get primary address
        # @return [Address, nil]
        def primary_address
          addresses&.first
        end

        # Convert to hash for JSON-LD serialization
        # @return [Hash]
        def to_hash
          hash = super
          hash[:names] = names.map(&:to_hash) if names&.any?
          hash[:addresses] = addresses.map(&:to_hash) if addresses&.any?
          hash[:identifications] = identifications.map(&:to_hash) if identifications&.any?
          hash[:contact_info] = contact_info.to_hash if contact_info&.present?
          hash[:organization_type] = organization_type if organization_type
          hash[:registration_number] = registration_number if registration_number
          hash[:incorporation_country] = incorporation_country if incorporation_country
          hash[:incorporation_date] = incorporation_date.to_s if incorporation_date
          hash[:industry] = industry if industry
          hash[:website] = website if website
          hash
        end

        # JSON mapping
        json do
          map :id, to: :id
          map :entity_type, to: :entity_type
          map :names, to: :names
          map :addresses, to: :addresses
          map :identifications, to: :identifications
          map :contact_info, to: :contact_info
          map :organization_type, to: :organization_type
          map :registration_number, to: :registration_number
          map :incorporation_country, to: :incorporation_country
          map :incorporation_date, to: :incorporation_date
          map :industry, to: :industry
          map :website, to: :website
          map :source_references, to: :source_references
          map :same_as, to: :same_as
          map :remarks, to: :remarks
        end

        # YAML mapping
        yaml do
          map :id, to: :id
          map :entity_type, to: :entity_type
          map :names, to: :names
          map :addresses, to: :addresses
          map :identifications, to: :identifications
          map :contact_info, to: :contact_info
          map :organization_type, to: :organization_type
          map :registration_number, to: :registration_number
          map :incorporation_country, to: :incorporation_country
          map :incorporation_date, to: :incorporation_date
          map :industry, to: :industry
          map :website, to: :website
          map :source_references, to: :source_references
          map :same_as, to: :same_as
          map :remarks, to: :remarks
        end
      end
    end
  end
end
