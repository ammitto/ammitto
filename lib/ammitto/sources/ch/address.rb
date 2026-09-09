# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Ch
      # Address in Swiss sanctions list
      class Address < Lutaml::Model::Serializable
        attribute :address_details, :string
        attribute :zip_code, :string

        xml do
          root 'address'
          map_element 'address-details', to: :address_details
          map_element 'zip-code', to: :zip_code
        end

        yaml do
          map 'address_details', to: :address_details
          map 'zip_code', to: :zip_code
        end
      end
    end
  end
end
