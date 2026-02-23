# frozen_string_literal: true

require_relative 'entity'

module Ammitto
  module Ontology
    module Entities
      # Represents a vessel (ship) subject to sanctions
      #
      # VesselEntity extends Entity with maritime-specific attributes
      # such as IMO number, flag state, tonnage, etc.
      #
      # @example Creating a vessel entity
      #   vessel = VesselEntity.new(
      #     id: "https://www.ammitto.org/entity/un_vessels/9288693",
      #     name: "Andaman Skies",
      #     imo_number: "9288693",
      #     flag_state: "DPRK",
      #     tonnage: 5000,
      #     build_year: 2004
      #   )
      #
      class VesselEntity < Entity
        # Vessel name (primary)
        # @return [String, nil]
        attribute :name, :string

        # Previous names
        # @return [Array<String>, nil]
        attribute :previous_names, :string, collection: true

        # IMO number (International Maritime Organization unique ID)
        # @return [String, nil]
        attribute :imo_number, :string

        # MMSI number (Maritime Mobile Service Identity)
        # @return [String, nil]
        attribute :mmsi_number, :string

        # Call sign
        # @return [String, nil]
        attribute :call_sign, :string

        # Flag state (country of registration)
        # @return [String, nil]
        attribute :flag_state, :string

        # Previous flag states
        # @return [Array<String>, nil]
        attribute :previous_flags, :string, collection: true

        # Vessel type (tanker, cargo, etc.)
        # @return [String, nil]
        attribute :vessel_type, :string

        # Gross tonnage
        # @return [Integer, nil]
        attribute :tonnage, :integer

        # Deadweight tonnage
        # @return [Integer, nil]
        attribute :deadweight, :integer

        # Year built
        # @return [Integer, nil]
        attribute :build_year, :integer

        # Ship builder
        # @return [String, nil]
        attribute :builder, :string

        # Port of registry
        # @return [String, nil]
        attribute :port_of_registry, :string

        # Registered owner
        # @return [String, nil]
        attribute :registered_owner, :string

        # Manager/operator
        # @return [String, nil]
        attribute :manager, :string

        # Length in meters
        # @return [Float, nil]
        attribute :length, :float

        def initialize(*args)
          super
          self.entity_type = 'vessel'
        end

        # Get primary name (alias for vessel name)
        # @return [String, nil]
        def primary_name
          name
        end

        # Get all names (current + previous)
        # @return [Array<String>]
        def all_names
          [name, *previous_names].compact
        end

        # Check if vessel has IMO number
        # @return [Boolean]
        def has_imo?
          imo_number&.match?(/^\d{7}$/)
        end

        # Get vessel info summary
        # @return [String]
        def info_summary
          parts = [name, imo_number, flag_state].compact
          parts.join(" / ")
        end

        # Convert to hash for JSON-LD serialization
        # @return [Hash]
        def to_hash
          hash = super
          hash[:name] = name if name
          hash[:previous_names] = previous_names if previous_names&.any?
          hash[:imo_number] = imo_number if imo_number
          hash[:mmsi_number] = mmsi_number if mmsi_number
          hash[:call_sign] = call_sign if call_sign
          hash[:flag_state] = flag_state if flag_state
          hash[:previous_flags] = previous_flags if previous_flags&.any?
          hash[:vessel_type] = vessel_type if vessel_type
          hash[:tonnage] = tonnage if tonnage
          hash[:deadweight] = deadweight if deadweight
          hash[:build_year] = build_year if build_year
          hash[:builder] = builder if builder
          hash[:port_of_registry] = port_of_registry if port_of_registry
          hash[:registered_owner] = registered_owner if registered_owner
          hash[:manager] = manager if manager
          hash[:length] = length if length
          hash
        end

        # JSON mapping
        json do
          map :id, to: :id
          map :entity_type, to: :entity_type
          map :name, to: :name
          map :previous_names, to: :previous_names
          map :imo_number, to: :imo_number
          map :mmsi_number, to: :mmsi_number
          map :call_sign, to: :call_sign
          map :flag_state, to: :flag_state
          map :previous_flags, to: :previous_flags
          map :vessel_type, to: :vessel_type
          map :tonnage, to: :tonnage
          map :deadweight, to: :deadweight
          map :build_year, to: :build_year
          map :builder, to: :builder
          map :port_of_registry, to: :port_of_registry
          map :registered_owner, to: :registered_owner
          map :manager, to: :manager
          map :length, to: :length
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
          map :imo_number, to: :imo_number
          map :mmsi_number, to: :mmsi_number
          map :call_sign, to: :call_sign
          map :flag_state, to: :flag_state
          map :previous_flags, to: :previous_flags
          map :vessel_type, to: :vessel_type
          map :tonnage, to: :tonnage
          map :deadweight, to: :deadweight
          map :build_year, to: :build_year
          map :builder, to: :builder
          map :port_of_registry, to: :port_of_registry
          map :registered_owner, to: :registered_owner
          map :manager, to: :manager
          map :length, to: :length
          map :source_references, to: :source_references
          map :same_as, to: :same_as
          map :remarks, to: :remarks
        end
      end
    end
  end
end
