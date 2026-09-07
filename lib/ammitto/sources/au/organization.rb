# frozen_string_literal: true

require_relative 'base_entity'

module Ammitto
  module Sources
    module Au
      # The Australian sanctions ontology as a whole, how the denormalized
      # CSV maps onto these objects and what the regimes and effects mean,
      # is in lib/ammitto/sources/au.rb.
      # Sanctioned organization (legal entity)
      class Organization < BaseEntity
        attribute :entity_type, :string, default: 'organization'

        yaml do
          map 'reference', to: :reference
          map 'entity_type', to: :entity_type
          map 'names', to: :names
          map 'address', to: :address
          map 'additional_info', to: :additional_info
          map 'sanction', to: :sanction
        end

        def self.from_csv_row(row)
          entity = new(
            reference: parse_base_reference(row['Reference']),
            entity_type: 'organization',
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
