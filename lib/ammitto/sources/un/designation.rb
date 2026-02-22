# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Un
      # Designation with multiple VALUE elements
      class Designation < Lutaml::Model::Serializable
        attribute :values, :string, collection: true

        xml do
          root 'DESIGNATION'
          map_element 'VALUE', to: :values
        end

        yaml do
          map 'values', to: :values
        end
      end
    end
  end
end
