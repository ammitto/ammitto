# frozen_string_literal: true

require 'lutaml/model'
require_relative 'immutable'
require_relative '../../utils/presence'
require_relative '../neo4j_adapter'

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
      class AddressModel < Lutaml::Model::Serializable
        include Neo4jAdapter

        # Neo4j configuration for Address
        neo4j_labels 'Address'
        neo4j_property :street, :city, :region, :country, :country_iso_code,
                       :postal_code, :po_box, :address_type, :street2, :state

        # Street address (building number and street name)
        # @return [String, nil]
        attribute :street, :string

        # Second street line, as the source split it
        # @return [String, nil]
        attribute :street2, :string

        # City / town / locality
        # @return [String, nil]
        attribute :city, :string

        # Region / state / province
        # @return [String, nil]
        attribute :region, :string

        # State as the source labelled it. Kept apart from region: a source
        # may state both, and they need not agree.
        # @return [String, nil]
        attribute :state, :string

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
          [street, street2, city, region, state, country, postal_code].any? { |v| Utils::Presence.present?(v) }
        end

        # Check if address is empty
        # @return [Boolean]
        def blank?
          !present?
        end

        # Get single-line address string
        # @return [String]
        def to_s
          parts = [street, street2, city, region, state, postal_code, country].compact
          parts.join(', ')
        end

        # Convert to hash for JSON-LD serialization
        # @return [Hash]
        def to_hash
          hash = {}
          hash[:street] = street if street
          hash[:street2] = street2 if street2
          hash[:city] = city if city
          hash[:region] = region if region
          hash[:state] = state if state
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
          map :street2, to: :street2
          map :state, to: :state
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
          map :street2, to: :street2
          map :state, to: :state
        end
      end
      private_constant :AddressModel

      class Address < AddressModel
        include Immutable
      end
    end
  end
end
