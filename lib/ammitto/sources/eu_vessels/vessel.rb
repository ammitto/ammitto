# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module EuVessels
      # Vessel represents a sanctioned vessel in the EU designated vessels list
      #
      class Vessel < Lutaml::Model::Serializable
        attribute :vessel_name, :string
        attribute :imo_number, :string
        attribute :date_of_application, :date

        # Create Vessel from row data hash
        # @param data [Hash] row data
        # @return [Vessel]
        def self.from_row_data(data)
          vessel = new
          vessel.vessel_name = data['vessel_name']
          vessel.imo_number = data['imo_number']&.to_s
          vessel.date_of_application = parse_date(data['date_of_application'])
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
            'date_of_application' => date_of_application&.iso8601
          }.compact
        end
      end
    end
  end
end
