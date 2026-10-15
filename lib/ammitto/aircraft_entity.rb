# frozen_string_literal: true

require_relative 'entity'
require_relative 'entity_link'
require_relative 'ontology/contracts'
require_relative 'ontology/entities/aircraft_entity'

module Ammitto
  # AircraftEntity represents a sanctioned aircraft
  #
  # Legacy facade: its fields are projected from
  # Ontology::Entities::AircraftEntity (see Ontology::Contracts). Renamed
  # here: +registration_number+ (canonical +registration+), +flag_state+
  # (+registration_country+), +owner+/+operator+ EntityLinks
  # (+owner_link+/+operator_link+) and the operator's name string
  # +operator_name+ (+operator+).
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
    Ontology::Contracts.declare_legacy_attributes(self)

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
      map 'name', to: :name
      map 'previousNames', to: :previous_names
      map 'icao24bit', to: :icao_24bit
      map 'registeredOwner', to: :registered_owner
      map 'operatorName', to: :operator_name
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
