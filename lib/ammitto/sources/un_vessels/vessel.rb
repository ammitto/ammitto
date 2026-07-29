# frozen_string_literal: true

require 'lutaml/model'

require_relative '../scalar_field'

module Ammitto
  module Sources
    module UnVessels
      # Simple name variant for YAML deserialization
      class NameVariant < Lutaml::Model::Serializable
        attribute :full_name, :string
        attribute :is_primary, :boolean, default: false

        yaml do
          map 'full_name', to: :full_name
          map 'is_primary', to: :is_primary
        end

        def to_hash
          { 'full_name' => full_name, 'is_primary' => is_primary }
        end
      end

      # Vessel represents a sanctioned vessel in the UN Designated Vessels List
      #
      class Vessel < Lutaml::Model::Serializable
        extend ScalarField

        attribute :id, :string
        attribute :entity_type, :string
        attribute :names, NameVariant, collection: true
        attribute :imo_number, :string
        attribute :flag_state, :string
        attribute :tonnage, :integer
        attribute :build_year, :integer
        attribute :designation_date, :date
        attribute :resolution, :string

        # YAML mapping for actual YAML structure. Deliberately NOT
        # key_value: the custom self.from_hash below shadows the Lutaml
        # hash deserializer, so hash parsing never consults these
        # mappings, and widening them would change the JSON contract
        # (JSON has no explicit block, so it keeps the attribute-name
        # key 'designation_date').
        yaml do
          map 'id', to: :id
          map 'entity_type', to: :entity_type
          map 'names', to: :names
          map 'imo_number', to: :imo_number
          map 'flag_state', to: :flag_state
          map 'tonnage', to: :tonnage
          map 'build_year', to: :build_year
          map 'date_designated', to: :designation_date
          map 'resolution', to: :resolution
        end

        # Get vessel name from names array (primary name or first name)
        # @return [String, nil]
        def vessel_name
          primary = names&.find(&:is_primary)
          primary&.full_name || names&.first&.full_name
        end

        # Get previous names from names array (non-primary names)
        # @return [Array<String>]
        def previous_names
          return [] if names.nil? || names.empty?

          names.reject(&:is_primary).map(&:full_name).compact
        end

        # Create Vessel from a data hash. Handles both the fetch-time
        # row shape (date under 'designation_date', no names) and the
        # serialized YAML shape the harmonize path loads (date under
        # 'date_designated', names present) — this method shadows the
        # Lutaml from_hash, so it must not drop the YAML-shape fields.
        # Every scalar field is read through fetch_scalar: this reader
        # shadows the Lutaml one, so it owes callers the same refusal of
        # a container in a single-value slot (see ScalarField).
        # @param data [Hash] row or YAML data
        # @return [Vessel]
        # @raise [ArgumentError] when a scalar field holds a container
        def self.from_hash(data)
          vessel = new
          vessel.id = fetch_scalar(data, 'id')
          vessel.entity_type = fetch_scalar(data, 'entity_type')
          vessel.names = Array(data['names']).map do |name|
            name.is_a?(NameVariant) ? name : NameVariant.from(:hash, name)
          end
          vessel.imo_number = fetch_scalar(data, 'imo_number')&.to_s
          vessel.flag_state = fetch_scalar(data, 'flag_state')
          # Assigned raw so the attribute's own Integer cast runs, as it
          # does for every string attribute here. A prior &.to_i
          # defeated that cast: "12,500" tonnage became 12 where
          # from_yaml yields nil, quietly inventing a plausible number.
          vessel.tonnage = fetch_scalar(data, 'tonnage')
          vessel.build_year = fetch_scalar(data, 'build_year')
          # The canonical serialized key wins whenever it is PRESENT,
          # even holding a blank — that is what the yaml mapping reads
          # and what #to_hash emits, so a serialized file resolves
          # exactly as from_yaml resolves it. 'designation_date' is the
          # fetch-time row alias, consulted only when the canonical key
          # is absent entirely.
          raw_date = if data.key?('date_designated')
                       fetch_scalar(data, 'date_designated')
                     else
                       fetch_scalar(data, 'designation_date')
                     end
          vessel.designation_date = parse_date(raw_date)
          vessel.resolution = fetch_scalar(data, 'resolution')
          vessel
        end

        # Parse date value
        def self.parse_date(value)
          return nil if value.nil?
          return value if value.is_a?(Date)

          begin
            Date.parse(value.to_s)
          rescue ArgumentError
            nil
          end
        end

        # Get unique identifier (IMO number)
        def unique_identifier
          "IMO-#{imo_number}"
        end

        # Get reference number (alias for unique_identifier)
        def reference_number
          unique_identifier
        end

        # Convert to hash for YAML serialization
        def to_hash
          {
            'id' => id,
            'entity_type' => entity_type,
            'names' => names&.map(&:to_hash),
            'imo_number' => imo_number,
            'flag_state' => flag_state,
            'tonnage' => tonnage,
            'build_year' => build_year,
            'date_designated' => designation_date&.iso8601,
            'resolution' => resolution
          }.compact
        end
      end
    end
  end
end
