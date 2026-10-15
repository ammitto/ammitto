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
        # Neo4j labels: include both specific type and base Entity
        neo4j_labels 'Aircraft', 'Entity'

        # Neo4j properties for aircraft-specific attributes
        neo4j_property :name, :serial_number, :registration, :icao_24bit,
                       :aircraft_type, :manufacturer, :build_year,
                       :registration_country, :registered_owner, :operator

        # Neo4j relationships
        neo4j_relationship :registered_in,
                           type: 'REGISTERED_IN',
                           target_class: 'Country',
                           target_key: :code

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

        # Earlier registrations (tail numbers), kept apart from
        # previous_names
        # @return [Array<String>, nil]
        attribute :previous_registrations, :string, collection: true

        # ICAO 24-bit address (hex)
        # @return [String, nil]
        attribute :icao_24bit, :string

        # Aircraft type/model
        # @return [String, nil]
        attribute :aircraft_type, :string

        # Model designation (737-800, A320, ...)
        # @return [String, nil]
        attribute :model, :string

        # Engine type (jet, turboprop, piston)
        # @return [String, nil]
        attribute :engine_type, :string

        # Manufacturer
        # @return [String, nil]
        attribute :manufacturer, :string

        # Year of manufacture
        # @return [Integer, nil]
        attribute :build_year, :integer

        # Country of registration
        # @return [String, nil]
        attribute :registration_country, :string

        # ISO 3166-1 alpha-2 code of the registration country
        # @return [String, nil]
        attribute :flag_state_iso_code, :string

        # Registered owner
        # @return [String, nil]
        attribute :registered_owner, :string

        # Operator
        # @return [String, nil]
        attribute :operator, :string

        # Owning company or person as a link to its entity
        # @return [ValueObjects::EntityLink, nil]
        attribute :owner_link, ValueObjects::EntityLink

        # Operating airline or company as a link to its entity; the
        # +operator+ string keeps the name as published
        # @return [ValueObjects::EntityLink, nil]
        attribute :operator_link, ValueObjects::EntityLink

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
          hash[:previous_registrations] = previous_registrations if previous_registrations&.any?
          hash[:icao_24bit] = icao_24bit if icao_24bit
          hash[:aircraft_type] = aircraft_type if aircraft_type
          hash[:model] = model if model
          hash[:engine_type] = engine_type if engine_type
          hash[:manufacturer] = manufacturer if manufacturer
          hash[:build_year] = build_year if build_year
          hash[:registration_country] = registration_country if registration_country
          hash[:flag_state_iso_code] = flag_state_iso_code if flag_state_iso_code
          hash[:registered_owner] = registered_owner if registered_owner
          hash[:operator] = operator if operator
          hash[:owner_link] = owner_link.to_hash if owner_link
          hash[:operator_link] = operator_link.to_hash if operator_link
          hash
        end

        # JSON mapping
        json do
          map :id, to: :id
          map :entity_type, to: :entity_type
          map :name, to: :name
          map :names, to: :names
          map :previous_names, to: :previous_names
          map :serial_number, to: :serial_number
          map :registration, to: :registration
          map :previous_registrations, to: :previous_registrations
          map :icao_24bit, to: :icao_24bit
          map :aircraft_type, to: :aircraft_type
          map :model, to: :model
          map :engine_type, to: :engine_type
          map :manufacturer, to: :manufacturer
          map :build_year, to: :build_year
          map :registration_country, to: :registration_country
          map :flag_state_iso_code, to: :flag_state_iso_code
          map :registered_owner, to: :registered_owner
          map :operator, to: :operator
          map :owner_link, to: :owner_link
          map :operator_link, to: :operator_link
          map :source_references, to: :source_references
          map :linked_entities, to: :linked_entities
          map :same_as, to: :same_as
          map :remarks, to: :remarks
          map :sanction_entry_ids, to: :sanction_entry_ids
        end

        # YAML mapping
        yaml do
          map :id, to: :id
          map :entity_type, to: :entity_type
          map :name, to: :name
          map :names, to: :names
          map :previous_names, to: :previous_names
          map :serial_number, to: :serial_number
          map :registration, to: :registration
          map :previous_registrations, to: :previous_registrations
          map :icao_24bit, to: :icao_24bit
          map :aircraft_type, to: :aircraft_type
          map :model, to: :model
          map :engine_type, to: :engine_type
          map :manufacturer, to: :manufacturer
          map :build_year, to: :build_year
          map :registration_country, to: :registration_country
          map :flag_state_iso_code, to: :flag_state_iso_code
          map :registered_owner, to: :registered_owner
          map :operator, to: :operator
          map :owner_link, to: :owner_link
          map :operator_link, to: :operator_link
          map :source_references, to: :source_references
          map :linked_entities, to: :linked_entities
          map :same_as, to: :same_as
          map :remarks, to: :remarks
          map :sanction_entry_ids, to: :sanction_entry_ids
        end
      end
    end
  end
end
