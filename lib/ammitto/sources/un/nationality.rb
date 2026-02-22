# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Un
      # Nationality wrapper for VALUE element
      class Nationality < Lutaml::Model::Serializable
        attribute :value, :string

        xml do
          root 'NATIONALITY'
          map_element 'VALUE', to: :value
        end

        yaml do
          map 'value', to: :value
        end
      end
    end
  end
end
