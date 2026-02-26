# frozen_string_literal: true

module Ammitto
  # VesselEntity represents a sanctioned vessel/ship
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
    attribute :entity_type, :string, default: 'vessel'
    attribute :imo_number, :string            # International Maritime Organization number
    attribute :mmsi, :string                  # Maritime Mobile Service Identity
    attribute :call_sign, :string             # Radio call sign
    attribute :flag_state, :string            # Country of registration
    attribute :flag_state_iso_code, :string   # ISO 3166-1 alpha-2
    attribute :vessel_type, :string           # Cargo, tanker, fishing, etc.
    attribute :vessel_type_code, :string      # Standardized vessel type code
    attribute :tonnage, Tonnage
    attribute :build_year, :integer
    attribute :builder, :string               # Shipyard/builder name
    attribute :length, :integer               # Length in meters
    attribute :gross_tonnage, :integer
    attribute :deadweight_tonnage, :integer
    attribute :owner, EntityLink              # Owning company
    attribute :operator, EntityLink           # Operating company
    attribute :registered_owner, EntityLink   # Registered owner
    attribute :technical_manager, EntityLink  # Technical management company
    attribute :previous_names, :string, collection: true
    attribute :previous_flags, :string, collection: true

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
