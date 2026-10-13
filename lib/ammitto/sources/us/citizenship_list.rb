# frozen_string_literal: true

require 'lutaml/model'
require_relative 'country_item'

module Ammitto
  module Sources
    module Us
      # Citizenship list wrapper
      class CitizenshipList < Lutaml::Model::Serializable
        attribute :items, CountryItem, collection: true

        xml do
          root 'citizenshipList'
          map_element 'citizenship', to: :items
        end

        yaml do
          map 'items', to: :items
        end

        # @return [Array<String>] the stated countries, in source order
        def countries
          items.filter_map(&:country)
        end
      end
    end
  end
end
