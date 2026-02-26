# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Ontology
    module ValueObjects
      # Represents a physical address
      #
      # Addresses can be associated with persons or organizations.
      # All fields are optional as sources may provide partial information.
      #
      # @example Creating an address
      #   address = Address.new(
      #     street: "123 Main Street",
      #     city: "Moscow",
      #     region: "Moscow Oblast",
      #     country: "Russia",
      #     country_iso_code: "RU",
      #     postal_code: "123456"
      #   )
      #
      class Address < Lutaml::Model::Serializable
        # Street address (building number and street name)
        # @return [String, nil]
        attribute :street, :string

        # City / town / locality
        # @return [String, nil]
        attribute :city, :string

        # Region / state / province
        # @return [String, nil]
        attribute :region, :string

        # Country name (free text)
        # @return [String, nil]
        attribute :country, :string

        # ISO 3166-1 alpha-2 country code
        # @return [String, nil]
        attribute :country_iso_code, :string

        # Postal / ZIP code
        # @return [String, nil]
        attribute :postal_code, :string

        # PO Box number
        # @return [String, nil]
        attribute :po_box, :string

        # Address type (registered, business, residential, etc.)
        # @return [String, nil]
        attribute :address_type, :string

        # Check if address has meaningful content
        # @return [Boolean]
        def present?
          [street, city, region, country, postal_code].any?(&:present?)
        end

        # Check if address is empty
        # @return [Boolean]
        def blank?
          !present?
        end

        # Get single-line address string
        # @return [String]
        def to_s
          parts = [street, city, region, postal_code, country].compact
          parts.join(', ')
        end

        # Convert to hash for JSON-LD serialization
        # @return [Hash]
        def to_hash
          hash = {}
          hash[:street] = street if street
          hash[:city] = city if city
          hash[:region] = region if region
          hash[:country] = country if country
          hash[:country_iso_code] = country_iso_code if country_iso_code
          hash[:postal_code] = postal_code if postal_code
          hash[:po_box] = po_box if po_box
          hash[:address_type] = address_type if address_type
          hash
        end

        # JSON mapping
        json do
          map :street, to: :street
          map :city, to: :city
          map :region, to: :region
          map :country, to: :country
          map :country_iso_code, to: :country_iso_code
          map :postal_code, to: :postal_code
          map :po_box, to: :po_box
          map :address_type, to: :address_type
        end

        # YAML mapping
        yaml do
          map :street, to: :street
          map :city, to: :city
          map :region, to: :region
          map :country, to: :country
          map :country_iso_code, to: :country_iso_code
          map :postal_code, to: :postal_code
          map :po_box, to: :po_box
          map :address_type, to: :address_type
        end
      end
    end
  end
end
