# frozen_string_literal: true

require 'lutaml/model'

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
        attribute :id, :string
        attribute :entity_type, :string
        attribute :names, NameVariant, collection: true
        attribute :imo_number, :string
        attribute :flag_state, :string
        attribute :tonnage, :integer
        attribute :build_year, :integer
        attribute :designation_date, :date
        attribute :resolution, :string

        # YAML mapping for actual YAML structure
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

        # Create Vessel from row data hash
        # @param data [Hash] row data
        # @return [Vessel]
        def self.from_hash(data)
          vessel = new
          vessel.id = data['id']
          vessel.entity_type = data['entity_type']
          vessel.imo_number = data['imo_number']&.to_s
          vessel.flag_state = data['flag_state']
          vessel.tonnage = data['tonnage']&.to_i
          vessel.build_year = data['build_year']&.to_i
          vessel.designation_date = parse_date(data['designation_date'])
          vessel.resolution = data['resolution']
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
