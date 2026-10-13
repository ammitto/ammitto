# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Us
      # One country entry of a nationalityList or citizenshipList. OFAC
      # gives both lists the same shape.
      class CountryItem < Lutaml::Model::Serializable
        attribute :uid, :string
        attribute :country, :string
        attribute :main_entry, :string

        xml do
          root 'country'
          map_element 'uid', to: :uid
          map_element 'country', to: :country
          map_element 'mainEntry', to: :main_entry
        end

        yaml do
          map 'uid', to: :uid
          map 'country', to: :country
          map 'main_entry', to: :main_entry
        end
      end
    end
  end
end
