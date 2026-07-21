# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Un
      # Wrapper for ENTITIES collection
      class EntitiesWrapper < Lutaml::Model::Serializable
        attribute :items, Entity, collection: true

        xml do
          root 'ENTITIES'
          map_element 'ENTITY', to: :items
        end

        yaml do
          map 'items', to: :items
        end
      end
    end
  end
end
