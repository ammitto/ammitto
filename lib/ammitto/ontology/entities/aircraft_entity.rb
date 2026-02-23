# frozen_string_literal: true

require_relative 'entity'

module Ammitto
  module Ontology
    module Entities
      # Represents an aircraft subject to sanctions
      #
      # AircraftEntity extends Entity with aviation-specific attributes
      # such as serial number, registration, manufacturer, etc.
      #
      # @example Creating an aircraft entity
      #   aircraft = AircraftEntity.new(
      #     id: "https://www.ammitto.org/entity/us/RA-12345",
      #     name: "RA-12345",
      #     serial_number: "12345",
      #     registration: "RA-12345",
      #     aircraft_type: "Boeing 737",
      #     manufacturer: "Boeing"
      #   )
      #
      class AircraftEntity < Entity
        # Aircraft name/tail number
        # @return [String, nil]
        attribute :name, :string

        # Previous names/registrations
        # @return [Array<String>, nil]
        attribute :previous_names, :string, collection: true

        # Manufacturer serial number (MSN)
        # @return [String, nil]
        attribute :serial_number, :string

        # Aircraft registration (tail number)
        # @return [String, nil]
        attribute :registration, :string

        # ICAO 24-bit address (hex)
        # @return [String, nil]
        attribute :icao_24bit, :string

        # Aircraft type/model
        # @return [String, nil]
        attribute :aircraft_type, :string

        # Manufacturer
        # @return [String, nil]
        attribute :manufacturer, :string

        # Year of manufacture
        # @return [Integer, nil]
        attribute :build_year, :integer

        # Country of registration
        # @return [String, nil]
        attribute :registration_country, :string

        # Registered owner
        # @return [String, nil]
        attribute :registered_owner, :string

        # Operator
        # @return [String, nil]
        attribute :operator, :string

        def initialize(*args)
          super
          self.entity_type = 'aircraft'
        end

        # Get primary name
        # @return [String, nil]
        def primary_name
          name || registration
        end

        # Get all names (current + previous)
        # @return [Array<String>]
        def all_names
          [name, registration, *previous_names].compact.uniq
        end

        # Convert to hash for JSON-LD serialization
        # @return [Hash]
        def to_hash
          hash = super
          hash[:name] = name if name
          hash[:previous_names] = previous_names if previous_names&.any?
          hash[:serial_number] = serial_number if serial_number
          hash[:registration] = registration if registration
          hash[:icao_24bit] = icao_24bit if icao_24bit
          hash[:aircraft_type] = aircraft_type if aircraft_type
          hash[:manufacturer] = manufacturer if manufacturer
          hash[:build_year] = build_year if build_year
          hash[:registration_country] = registration_country if registration_country
          hash[:registered_owner] = registered_owner if registered_owner
          hash[:operator] = operator if operator
          hash
        end

        # JSON mapping
        json do
          map :id, to: :id
          map :entity_type, to: :entity_type
          map :name, to: :name
          map :previous_names, to: :previous_names
          map :serial_number, to: :serial_number
          map :registration, to: :registration
          map :icao_24bit, to: :icao_24bit
          map :aircraft_type, to: :aircraft_type
          map :manufacturer, to: :manufacturer
          map :build_year, to: :build_year
          map :registration_country, to: :registration_country
          map :registered_owner, to: :registered_owner
          map :operator, to: :operator
          map :source_references, to: :source_references
          map :same_as, to: :same_as
          map :remarks, to: :remarks
        end

        # YAML mapping
        yaml do
          map :id, to: :id
          map :entity_type, to: :entity_type
          map :name, to: :name
          map :previous_names, to: :previous_names
          map :serial_number, to: :serial_number
          map :registration, to: :registration
          map :icao_24bit, to: :icao_24bit
          map :aircraft_type, to: :aircraft_type
          map :manufacturer, to: :manufacturer
          map :build_year, to: :build_year
          map :registration_country, to: :registration_country
          map :registered_owner, to: :registered_owner
          map :operator, to: :operator
          map :source_references, to: :source_references
          map :same_as, to: :same_as
          map :remarks, to: :remarks
        end
      end
    end
  end
end
