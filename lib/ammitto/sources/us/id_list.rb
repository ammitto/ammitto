# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Us
      # ID list wrapper
      class IdList < Lutaml::Model::Serializable
        attribute :items, Id, collection: true

        xml do
          root 'idList'
          map_element 'id', to: :items
        end

        yaml do
          map 'items', to: :items
        end
      end
    end
  end
end
