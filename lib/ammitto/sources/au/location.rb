# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Au
      # The Australian sanctions ontology as a whole, how the denormalized
      # CSV maps onto these objects and what the regimes and effects mean,
      # is in lib/ammitto/sources/au.rb.
      # Geographic location
      class Location < Lutaml::Model::Serializable
        attribute :raw_value, :string
        attribute :city, :string
        attribute :region, :string # State, province
        attribute :country, :string

        def self.parse(location_str)
          return nil if location_str.nil? || location_str.empty?

          location = new(raw_value: location_str.strip)

          # Try to parse "City, Region, Country" format
          parts = location_str.split(',').map(&:strip)

          case parts.length
          when 1
            # Just a city or country
            location.country = parts[0]
          when 2
            location.city = parts[0]
            location.country = parts[1]
          when 3
            location.city = parts[0]
            location.region = parts[1]
            location.country = parts[2]
          else
            location.raw_value = location_str
          end

          location
        end

        def to_s
          raw_value
        end
      end
    end
  end
end
