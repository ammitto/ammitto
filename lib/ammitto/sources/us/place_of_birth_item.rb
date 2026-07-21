# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Us
      # Place of birth item
      class PlaceOfBirthItem < Lutaml::Model::Serializable
        attribute :uid, :string
        attribute :place_of_birth, :string
        attribute :main_entry, :string

        xml do
          root 'placeOfBirthItem'
          map_element 'uid', to: :uid
          map_element 'placeOfBirth', to: :place_of_birth
          map_element 'mainEntry', to: :main_entry
        end

        yaml do
          map 'uid', to: :uid
          map 'place_of_birth', to: :place_of_birth
          map 'main_entry', to: :main_entry
        end
      end
    end
  end
end
