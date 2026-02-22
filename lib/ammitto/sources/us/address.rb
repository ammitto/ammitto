# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Us
      # Address entry
      class Address < Lutaml::Model::Serializable
        attribute :uid, :string
        attribute :address1, :string
        attribute :address2, :string
        attribute :address3, :string
        attribute :city, :string
        attribute :state_or_province, :string
        attribute :postal_code, :string
        attribute :country, :string

        xml do
          root 'address'
          map_element 'uid', to: :uid
          map_element 'address1', to: :address1
          map_element 'address2', to: :address2
          map_element 'address3', to: :address3
          map_element 'city', to: :city
          map_element 'stateOrProvince', to: :state_or_province
          map_element 'postalCode', to: :postal_code
          map_element 'country', to: :country
        end

        yaml do
          map 'uid', to: :uid
          map 'address1', to: :address1
          map 'address2', to: :address2
          map 'address3', to: :address3
          map 'city', to: :city
          map 'state_or_province', to: :state_or_province
          map 'postal_code', to: :postal_code
          map 'country', to: :country
        end
      end
    end
  end
end
