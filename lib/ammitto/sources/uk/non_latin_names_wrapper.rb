# frozen_string_literal: true

require 'lutaml/model'
require_relative 'non_latin_name'

module Ammitto
  module Sources
    module Uk
      # Wrapper for NonLatinNames collection
      class NonLatinNamesWrapper < Lutaml::Model::Serializable
        attribute :items, NonLatinName, collection: true

        xml do
          root 'NonLatinNames'
          map_element 'NonLatinName', to: :items
        end

        key_value do
          map 'names', to: :items
        end
      end
    end
  end
end
