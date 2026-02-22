# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Un
      # Wrapper for INDIVIDUALS collection
      class IndividualsWrapper < Lutaml::Model::Serializable
        attribute :items, Individual, collection: true

        xml do
          root 'INDIVIDUALS'
          map_element 'INDIVIDUAL', to: :items
        end

        yaml do
          map 'items', to: :items
        end
      end
    end
  end
end
