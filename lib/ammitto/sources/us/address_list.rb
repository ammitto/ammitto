# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Us
      # Address list wrapper
      class AddressList < Lutaml::Model::Serializable
        attribute :items, Address, collection: true

        xml do
          root 'addressList'
          map_element 'address', to: :items
        end

        yaml do
          map 'items', to: :items
        end
      end
    end
  end
end
