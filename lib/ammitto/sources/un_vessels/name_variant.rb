# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module UnVessels
      # Simple name variant for YAML deserialization
      class NameVariant < Lutaml::Model::Serializable
        attribute :full_name, :string
        attribute :is_primary, :boolean, default: false

        yaml do
          map 'full_name', to: :full_name
          map 'is_primary', to: :is_primary
        end

        def to_hash
          { 'full_name' => full_name, 'is_primary' => is_primary }
        end
      end
    end
  end
end
