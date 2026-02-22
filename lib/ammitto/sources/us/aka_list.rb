# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Us
      # AKA list wrapper
      class AkaList < Lutaml::Model::Serializable
        attribute :items, Aka, collection: true

        xml do
          root 'akaList'
          map_element 'aka', to: :items
        end

        yaml do
          map 'items', to: :items
        end
      end
    end
  end
end
