# frozen_string_literal: true

require 'lutaml/model'
require_relative 'instrument'
require_relative 'entity'

module Ammitto
  module Sources
    module Cn
      # Sanction details block from YAML
      class SanctionDetails < Lutaml::Model::Serializable
        attribute :instruments, Instrument, collection: true
        attribute :entities, Entity, collection: true

        key_value do
          map 'instruments', to: :instruments
          map 'entities', to: :entities
        end
      end
    end
  end
end
