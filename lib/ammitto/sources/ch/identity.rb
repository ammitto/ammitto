# frozen_string_literal: true

require 'lutaml/model'
require_relative 'address'
require_relative 'day_month_year'
require_relative 'name'

module Ammitto
  module Sources
    module Ch
      # Identity (person or entity) in Swiss sanctions list
      class Identity < Lutaml::Model::Serializable
        attribute :ssid, :string
        attribute :main, :string
        attribute :entity_type, :string # Serialized for proper entity type detection
        attribute :names, Name, collection: true
        attribute :day_month_year, DayMonthYear
        attribute :addresses, Address, collection: true

        xml do
          root 'identity'
          map_attribute 'ssid', to: :ssid
          map_attribute 'main', to: :main
          map_element 'name', to: :names
          map_element 'day-month-year', to: :day_month_year
          map_element 'address', to: :addresses
        end

        yaml do
          map 'ssid', to: :ssid
          map 'main', to: :main
          map 'entity_type', to: :entity_type
          map 'names', to: :names
          map 'day_month_year', to: :day_month_year
          map 'addresses', to: :addresses
        end

        def full_name
          names.first&.full_name
        end

        # Check if this is a person based on name parts (without calling entity_type)
        def person?
          names.any? { |n| n.name_parts.any? { |p| p.name_part_type == 'given-name' } }
        end

        # Compute entity_type if not set
        def entity_type
          return @entity_type if @entity_type && !@entity_type.empty?

          person? ? 'person' : 'organization'
        end
      end
    end
  end
end
