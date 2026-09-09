# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Ch
      # Sanctions program in Swiss sanctions list
      class SanctionsProgram < Lutaml::Model::Serializable
        attribute :ssid, :string
        attribute :program_keys, :string, collection: true

        xml do
          root 'sanctions-program'
          map_attribute 'ssid', to: :ssid
          map_element 'program-key', to: :program_keys
        end

        yaml do
          map 'ssid', to: :ssid
          map 'program_keys', to: :program_keys
        end
      end
    end
  end
end
