# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Un
      # Individual place of birth from UN sanctions
      class IndividualPlaceOfBirth < Lutaml::Model::Serializable
        attribute :city, :string
        attribute :state_province, :string
        attribute :country, :string

        xml do
          root 'INDIVIDUAL_PLACE_OF_BIRTH'
          map_element 'CITY', to: :city
          map_element 'STATE_PROVINCE', to: :state_province
          map_element 'COUNTRY', to: :country
        end

        yaml do
          map 'city', to: :city
          map 'state_province', to: :state_province
          map 'country', to: :country
        end
      end
    end
  end
end
