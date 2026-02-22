# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Us
      # Place of birth list wrapper
      class PlaceOfBirthList < Lutaml::Model::Serializable
        attribute :items, PlaceOfBirthItem, collection: true

        xml do
          root 'placeOfBirthList'
          map_element 'placeOfBirthItem', to: :items
        end

        yaml do
          map 'items', to: :items
        end
      end
    end
  end
end
