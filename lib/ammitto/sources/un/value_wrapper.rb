# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Un
      # Wrapper for VALUE elements
      #
      # Many UN elements have nested VALUE elements
      class ValueWrapper < Lutaml::Model::Serializable
        attribute :value, :string, collection: true

        xml do
          root 'VALUE'
          map_content to: :value
        end

        yaml do
          map 'value', to: :value
        end
      end
    end
  end
end
