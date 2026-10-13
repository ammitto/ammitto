# frozen_string_literal: true

require 'lutaml/model'
require_relative 'national_identifier'

module Ammitto
  module Sources
    module Uk
      # Wrapper for the <NationalIdentifierDetails> collection
      class NationalIdentifierDetails < Lutaml::Model::Serializable
        attribute :items, NationalIdentifier, collection: true

        xml do
          root 'NationalIdentifierDetails'
          map_element 'NationalIdentifier', to: :items
        end

        key_value do
          map 'national_identifiers', to: :items
        end
      end
    end
  end
end
