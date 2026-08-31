# frozen_string_literal: true

require 'lutaml/model'
require_relative 'modification'
require_relative 'modification_instrument'

module Ammitto
  module Sources
    module Cn
      # Modification block from YAML
      class ModificationBlock < Lutaml::Model::Serializable
        attribute :instruments, ModificationInstrument, collection: true
        attribute :modifications, Modification, collection: true

        key_value do
          map 'instruments', to: :instruments
          map 'modifications', to: :modifications
        end
      end
    end
  end
end
