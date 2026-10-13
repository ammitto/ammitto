# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Un
      # Wrapper for VALUE elements
      #
      # Many UN elements have nested VALUE elements. The mapping is on the
      # inner <VALUE>: reading the content of the outer element (LIST_TYPE,
      # LAST_DAY_UPDATED) returns only the whitespace around it.
      class ValueWrapper < Lutaml::Model::Serializable
        attribute :value, :string, collection: true

        xml do
          map_element 'VALUE', to: :value
        end

        yaml do
          map 'value', to: :value
        end
      end
    end
  end
end
