# frozen_string_literal: true

require 'lutaml/model'
require_relative 'entity'
require_relative 'instrument'

module Ammitto
  module Sources
    module Ru
      # The instruments and parties an announcement carries.
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
