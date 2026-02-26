# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Un
      # Individual address from UN sanctions
      class IndividualAddress < Lutaml::Model::Serializable
        attribute :street, :string
        attribute :city, :string
        attribute :state_province, :string
        attribute :country, :string
        attribute :note, :string

        xml do
          root 'INDIVIDUAL_ADDRESS'
          map_element 'STREET', to: :street
          map_element 'CITY', to: :city
          map_element 'STATE_PROVINCE', to: :state_province
          map_element 'COUNTRY', to: :country
          map_element 'NOTE', to: :note
        end

        yaml do
          map 'street', to: :street
          map 'city', to: :city
          map 'state_province', to: :state_province
          map 'country', to: :country
          map 'note', to: :note
        end
      end
    end
  end
end
