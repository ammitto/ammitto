# frozen_string_literal: true

require 'lutaml/model'
require_relative 'identity'

module Ammitto
  module Sources
    module Ch
      # Individual in Swiss sanctions list
      class Individual < Lutaml::Model::Serializable
        attribute :identity, Identity
        attribute :justification, :string

        xml do
          root 'individual'
          map_element 'identity', to: :identity
          map_element 'justification', to: :justification
        end

        yaml do
          map 'identity', to: :identity
          map 'justification', to: :justification
        end
      end
    end
  end
end
