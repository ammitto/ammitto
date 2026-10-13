# frozen_string_literal: true

require 'lutaml/model'
require_relative 'ship'

module Ammitto
  module Sources
    module Uk
      # The <ShipDetails> element of a UK designation, which holds one
      # <Ship> block.
      class ShipDetails < Lutaml::Model::Serializable
        attribute :ship, Ship

        xml do
          root 'ShipDetails'
          map_element 'Ship', to: :ship
        end

        key_value do
          map 'ship', to: :ship
        end
      end
    end
  end
end
