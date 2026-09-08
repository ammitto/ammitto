# frozen_string_literal: true

require 'lutaml/model'
require_relative 'name'

module Ammitto
  module Sources
    module Uk
      # Wrapper for Names collection
      class NamesWrapper < Lutaml::Model::Serializable
        attribute :items, Name, collection: true

        xml do
          root 'Names'
          map_element 'Name', to: :items
        end

        key_value do
          map 'names', to: :items
        end
      end
    end
  end
end
