# frozen_string_literal: true

require 'lutaml/model'
require_relative 'passport'

module Ammitto
  module Sources
    module Uk
      # Wrapper for the <PassportDetails> collection
      class PassportDetails < Lutaml::Model::Serializable
        attribute :items, Passport, collection: true

        xml do
          root 'PassportDetails'
          map_element 'Passport', to: :items
        end

        key_value do
          map 'passports', to: :items
        end
      end
    end
  end
end
