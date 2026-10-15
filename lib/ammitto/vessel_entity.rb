# frozen_string_literal: true

require_relative 'entity'
require_relative 'entity_link'
require_relative 'tonnage'
require_relative 'ontology/contracts'
require_relative 'ontology/entities/vessel_entity'

module Ammitto
  # VesselEntity represents a sanctioned vessel/ship
  #
  # Legacy facade: its fields are projected from
  # Ontology::Entities::VesselEntity (see Ontology::Contracts). Renamed
  # here: +mmsi+ (canonical +mmsi_number+), +deadweight_tonnage+
  # (+deadweight+), +owner+/+operator+/+registered_owner+ EntityLinks
  # (+owner_link+/+operator_link+/+registered_owner_link+) and the
  # registered owner's name string +registered_owner_name+
  # (+registered_owner+). +length+ stays an Integer here.
  #
  # @example Creating a vessel entity
  #   VesselEntity.new(
  #     id: "https://ammitto.org/entity/789",
  #     names: [NameVariant.new(full_name: "MV Pacific Star", is_primary: true)],
  #     imo_number: "1234567",
  #     flag_state: "Panama"
  #   )
  #
  class VesselEntity < Entity
    Ontology::Contracts.declare_legacy_attributes(self)

    json do
      map 'entityType', to: :entity_type
      map 'imoNumber', to: :imo_number
      map 'mmsi', to: :mmsi
      map 'callSign', to: :call_sign
      map 'flagState', to: :flag_state
      map 'flagStateIsoCode', to: :flag_state_iso_code
      map 'vesselType', to: :vessel_type
      map 'vesselTypeCode', to: :vessel_type_code
      map 'tonnage', to: :tonnage
      map 'buildYear', to: :build_year
      map 'builder', to: :builder
      map 'length', to: :length
      map 'grossTonnage', to: :gross_tonnage
      map 'deadweightTonnage', to: :deadweight_tonnage
      map 'owner', to: :owner
      map 'operator', to: :operator
      map 'registeredOwner', to: :registered_owner
      map 'technicalManager', to: :technical_manager
      map 'previousNames', to: :previous_names
      map 'previousFlags', to: :previous_flags
      map 'name', to: :name
      map 'portOfRegistry', to: :port_of_registry
      map 'registeredOwnerName', to: :registered_owner_name
      map 'manager', to: :manager
    end

    # Check if this vessel matches a search term
    # @param term [String] the search term
    # @return [Boolean] whether there's a match
    def matches?(term)
      return true if super

      term_lower = term.downcase

      # Check IMO number
      return true if imo_number&.include?(term)

      # Check MMSI
      return true if mmsi&.include?(term)

      # Check call sign
      return true if call_sign&.downcase&.include?(term_lower)

      # Check flag state
      return true if flag_state&.downcase&.include?(term_lower)

      # Check previous names
      previous_names.any? { |n| n.downcase.include?(term_lower) }
    end
  end
end
