# frozen_string_literal: true

require_relative 'base_entity'

module Ammitto
  module Sources
    module Au
      # The Australian sanctions ontology as a whole, how the denormalized
      # CSV maps onto these objects and what the regimes and effects mean,
      # is in lib/ammitto/sources/au.rb.
      # A concrete model keeps unrecognized records visible to fetch --prune.
      class GenericEntity < BaseEntity
        attribute :entity_type, :string

        yaml do
          map 'reference', to: :reference
          # A blank Type must still reach harmonize as a generic record, not
          # fall into the organization branch when the key goes missing.
          map 'entity_type', to: :entity_type, render_nil: true, render_empty: true
          map 'names', to: :names
          map 'address', to: :address
          map 'additional_info', to: :additional_info
          map 'sanction', to: :sanction
        end

        # Every spelling the known models are written or read back under.
        KNOWN_ENTITY_TYPES = %w[person organization vessel Individual Entity Vessel].freeze

        # @param data [Hash] one fetched record
        # @return [Boolean] whether the record was written for a Type the
        #   known models do not cover
        def self.record?(data)
          data.key?('entity_type') && !KNOWN_ENTITY_TYPES.include?(data['entity_type'])
        end

        def self.from_csv_row(row)
          entity = new(
            reference: parse_base_reference(row['Reference']),
            entity_type: row['Type'],
            names: [],
            address: row['Address'],
            additional_info: row['Additional Information'],
            sanction: nil
          )
          entity.merge_row(row)
          entity
        end
      end
    end
  end
end
