# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Us
      # Date of birth list wrapper
      class DateOfBirthList < Lutaml::Model::Serializable
        attribute :items, DateOfBirthItem, collection: true

        xml do
          root 'dateOfBirthList'
          map_element 'dateOfBirthItem', to: :items
        end

        yaml do
          map 'items', to: :items
        end
      end
    end
  end
end
