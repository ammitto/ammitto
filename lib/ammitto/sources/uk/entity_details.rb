# frozen_string_literal: true

require 'lutaml/model'
require_relative 'legal_entity'

module Ammitto
  module Sources
    module Uk
      # The <EntityDetails> element of a UK designation, which holds one
      # <Entity> block.
      class EntityDetails < Lutaml::Model::Serializable
        attribute :entity, LegalEntity

        xml do
          root 'EntityDetails'
          map_element 'Entity', to: :entity
        end

        key_value do
          map 'entity', to: :entity
        end

        # @return [Array<String>]
        def business_registration_numbers
          entity&.business_registration_numbers || []
        end
      end
    end
  end
end
