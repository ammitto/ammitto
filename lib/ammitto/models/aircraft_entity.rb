# frozen_string_literal: true

module Ammitto
  # AircraftEntity represents a sanctioned aircraft
  #
  # @example Creating an aircraft entity
  #   AircraftEntity.new(
  #     id: "https://ammitto.org/entity/101",
  #     names: [NameVariant.new(full_name: "RA-12345", is_primary: true)],
  #     registration_number: "RA-12345",
  #     manufacturer: "Boeing",
  #     model: "737-800"
  #   )
  #
  class AircraftEntity < Entity
    attribute :entity_type, :string, default: 'aircraft'
    attribute :serial_number, :string         # Manufacturer serial number
    attribute :manufacturer, :string          # Boeing, Airbus, etc.
    attribute :model, :string                 # 737-800, A320, etc.
    attribute :registration_number, :string   # Tail number
    attribute :flag_state, :string            # Country of registration
    attribute :flag_state_iso_code, :string   # ISO 3166-1 alpha-2
    attribute :build_year, :integer
    attribute :aircraft_type, :string         # Passenger, cargo, private, etc.
    attribute :engine_type, :string           # Jet, turboprop, piston
    attribute :owner, EntityLink              # Owning company/person
    attribute :operator, EntityLink           # Operating airline/company
    attribute :previous_registrations, :string, collection: true

    json do
      map 'entityType', to: :entity_type
      map 'serialNumber', to: :serial_number
      map 'manufacturer', to: :manufacturer
      map 'model', to: :model
      map 'registrationNumber', to: :registration_number
      map 'flagState', to: :flag_state
      map 'flagStateIsoCode', to: :flag_state_iso_code
      map 'buildYear', to: :build_year
      map 'aircraftType', to: :aircraft_type
      map 'engineType', to: :engine_type
      map 'owner', to: :owner
      map 'operator', to: :operator
      map 'previousRegistrations', to: :previous_registrations
    end

    # Check if this aircraft matches a search term
    # @param term [String] the search term
    # @return [Boolean] whether there's a match
    def matches?(term)
      return true if super

      term_lower = term.downcase

      # Check serial number
      return true if serial_number&.include?(term)

      # Check registration number
      return true if registration_number&.downcase&.include?(term_lower)

      # Check manufacturer
      return true if manufacturer&.downcase&.include?(term_lower)

      # Check model
      return true if model&.downcase&.include?(term_lower)

      # Check flag state
      return true if flag_state&.downcase&.include?(term_lower)

      # Check previous registrations
      previous_registrations.any? { |r| r.downcase.include?(term_lower) }
    end
  end
end
