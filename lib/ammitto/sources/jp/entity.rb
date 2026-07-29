# frozen_string_literal: true

require 'lutaml/model'

require_relative '../scalar_field'

module Ammitto
  module Sources
    module Jp
      # Entity represents a sanctioned entity in the Japan End-User List
      #
      class Entity < Lutaml::Model::Serializable
        extend ScalarField

        attribute :id, :string
        attribute :name, :string
        attribute :name_ja, :string
        attribute :entity_type, :string
        attribute :addresses, :string, collection: true
        attribute :source_url, :string
        attribute :remarks, :string

        # Create Entity from row data hash.
        #
        # Every scalar field is read through fetch_scalar: this reader
        # shadows the Lutaml one, so it owes callers the same refusal of
        # a container in a single-value slot (see ScalarField).
        # @param data [Hash] row data
        # @return [Entity]
        # @raise [ArgumentError] when a scalar field holds a container
        def self.from_hash(data)
          entity = new
          entity.id = fetch_scalar(data, 'id')
          entity.name = fetch_scalar(data, 'name')
          entity.name_ja = fetch_scalar(data, 'name_ja')
          entity.entity_type =
            map_entity_type(fetch_scalar(data, 'entity_type'))
          entity.addresses = Array(data['addresses'])
          entity.source_url = fetch_scalar(data, 'source_url')
          entity.remarks = fetch_scalar(data, 'remarks')
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

        # Get unique identifier. Returns nil when the record's id holds
        # no sanitizable content (nil, empty, whitespace or
        # punctuation-only): a bare "JP-" prefix — or "JP-!!!" — would
        # sanitize to the constant "jp" and collapse every such Japanese
        # entity into entity/jp/jp, so the unusable id must flow through
        # to the IRI layer's MissingLocalIdError instead.
        def unique_identifier
          return nil unless id.to_s.match?(/[a-zA-Z0-9_]/)

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
