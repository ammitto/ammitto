# frozen_string_literal: true

require 'lutaml/model'
require_relative 'identity'

module Ammitto
  module Sources
    module Ch
      # SECO's object wrapper carries vessels separately from organizations.
      class SanctionedObject < Lutaml::Model::Serializable
        attribute :object_type, :string
        attribute :identity, Identity
        attribute :justification, :string
        attribute :other_information, :string

        xml do
          root 'object'
          map_attribute 'object-type', to: :object_type
          map_element 'identity', to: :identity
          map_element 'justification', to: :justification
          map_element 'other-information', to: :other_information
        end

        yaml do
          map 'object_type', to: :object_type
          map 'identity', to: :identity
          map 'justification', to: :justification
          map 'other_information', to: :other_information
        end

        # Accept only the explicit IMO label, including SECO's observed
        # "IMO Numbe" typo; arbitrary seven-digit prose is not an identifier.
        def imo_number
          other_information&.match(/\bIMO\s+Numbe(?:r)?\s*:\s*(\d{7})(?!\d)/i)&.[](1)
        end
      end
    end
  end
end
