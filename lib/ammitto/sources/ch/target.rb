# frozen_string_literal: true

require 'lutaml/model'
require_relative 'entity'
require_relative 'individual'

module Ammitto
  module Sources
    module Ch
      # Target in Swiss sanctions list (contains individual or entity)
      class Target < Lutaml::Model::Serializable
        attribute :ssid, :string
        attribute :sanctions_set_id, :string
        attribute :entity_type, :string # Serialized for proper entity type detection
        attribute :individual, Individual
        attribute :entity, Entity

        xml do
          root 'target'
          map_attribute 'ssid', to: :ssid
          map_element 'sanctions-set-id', to: :sanctions_set_id
          map_element 'individual', to: :individual
          map_element 'entity', to: :entity
        end

        yaml do
          map 'ssid', to: :ssid
          map 'sanctions_set_id', to: :sanctions_set_id
          map 'entity_type', to: :entity_type
          map 'individual', to: :individual
          map 'entity', to: :entity
        end

        def identity
          individual&.identity || entity&.identity
        end

        def full_name
          identity&.full_name
        end

        # Compute entity_type if not set
        def entity_type
          return @entity_type if @entity_type && !@entity_type.empty?

          individual ? 'person' : 'organization'
        end
      end
    end
  end
end
