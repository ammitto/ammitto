# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Jp
      # Entity represents a sanctioned entity in the Japan End-User List
      #
      class Entity < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :name, :string
        attribute :name_ja, :string
        attribute :entity_type, :string
        attribute :addresses, :string, collection: true
        attribute :source_url, :string
        attribute :remarks, :string

        # Create Entity from row data hash
        # @param data [Hash] row data
        # @return [Entity]
        def self.from_hash(data)
          entity = new
          entity.id = data['id']
          entity.name = data['name']
          entity.name_ja = data['name_ja']
          entity.entity_type = map_entity_type(data['entity_type'])
          entity.addresses = Array(data['addresses'])
          entity.source_url = data['source_url']
          entity.remarks = data['remarks']
          entity
        end

        # Map entity type to standard type
        def self.map_entity_type(type)
          case type.to_s.downcase
          when /person|individual/
            'person'
          when /organization|company|entity/
            'organization'
          else
            'organization'
          end
        end

        # Get unique identifier
        def unique_identifier
          "JP-#{id}"
        end

        # Get reference number (alias for unique_identifier)
        def reference_number
          unique_identifier
        end

        # Convert to hash for YAML serialization
        def to_hash
          {
            'id' => id,
            'name' => name,
            'name_ja' => name_ja,
            'entity_type' => entity_type,
            'addresses' => addresses,
            'source_url' => source_url,
            'remarks' => remarks
          }.compact
        end
      end
    end
  end
end
