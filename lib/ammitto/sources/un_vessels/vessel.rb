# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module UnVessels
      # Vessel represents a sanctioned vessel in the UN Designated Vessels List
      #
      class Vessel < Lutaml::Model::Serializable
        attribute :vessel_name, :string
        attribute :imo_number, :string
        attribute :flag_state, :string
        attribute :previous_names, :string, collection: true
        attribute :tonnage, :integer
        attribute :build_year, :integer
        attribute :designation_date, :date
        attribute :resolution, :string

        # Create Vessel from row data hash
        # @param data [Hash] row data
        # @return [Vessel]
        def self.from_hash(data)
          vessel = new
          vessel.vessel_name = data['vessel_name']
          vessel.imo_number = data['imo_number']&.to_s
          vessel.flag_state = data['flag_state']
          vessel.previous_names = Array(data['previous_names'])
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
            'vessel_name' => vessel_name,
            'imo_number' => imo_number,
            'flag_state' => flag_state,
            'previous_names' => previous_names,
            'tonnage' => tonnage,
            'build_year' => build_year,
            'designation_date' => designation_date&.iso8601,
            'resolution' => resolution
          }.compact
        end
      end
    end
  end
end
