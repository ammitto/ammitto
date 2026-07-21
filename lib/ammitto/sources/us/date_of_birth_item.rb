# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Us
      # Date of birth item
      class DateOfBirthItem < Lutaml::Model::Serializable
        attribute :uid, :string
        attribute :date_of_birth, :string
        attribute :main_entry, :string

        xml do
          root 'dateOfBirthItem'
          map_element 'uid', to: :uid
          map_element 'dateOfBirth', to: :date_of_birth
          map_element 'mainEntry', to: :main_entry
        end

        yaml do
          map 'uid', to: :uid
          map 'date_of_birth', to: :date_of_birth
          map 'main_entry', to: :main_entry
        end
      end
    end
  end
end
