# frozen_string_literal: true

require 'lutaml/model'
require_relative 'address'

module Ammitto
  module Sources
    module Uk
      # Wrapper for Addresses collection
      class AddressesWrapper < Lutaml::Model::Serializable
        attribute :items, Address, collection: true

        xml do
          root 'Addresses'
          map_element 'Address', to: :items
        end

        key_value do
          map 'addresses', to: :items
        end
      end
    end
  end
end
