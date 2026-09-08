# frozen_string_literal: true

require_relative 'base_entity'

module Ammitto
  module Sources
    module Au
      # The Australian sanctions ontology as a whole, how the denormalized
      # CSV maps onto these objects and what the regimes and effects mean,
      # is in lib/ammitto/sources/au.rb.
      # Sanctioned vessel (ship)
      class Vessel < BaseEntity
        attribute :entity_type, :string, default: 'vessel'
        attribute :imo_number, :string
        attribute :previous_names, :string, collection: true

        yaml do
          map 'reference', to: :reference
          map 'entity_type', to: :entity_type
          map 'names', to: :names
          map 'address', to: :address
          map 'additional_info', to: :additional_info
          map 'sanction', to: :sanction
          map 'imo_number', to: :imo_number
          map 'previous_names', to: :previous_names
        end

        def self.from_csv_row(row)
          entity = new(
            reference: parse_base_reference(row['Reference']),
            entity_type: 'vessel',
            names: [],
            address: nil, # Vessels don't have addresses
            additional_info: row['Additional Information'],
            sanction: nil,
            imo_number: row['IMO Number'],
            previous_names: []
          )
          entity.merge_row(row)

          # Parse previous names from additional info
          entity.extract_previous_names

          entity
        end

        def extract_previous_names
          return unless additional_info&.include?('Previous names include')

          match = additional_info.match(/Previous names include\s+(.+?)(?:\.|$)/)
          return unless match

          match[1].split(',').map(&:strip).reject(&:empty?).each do |name|
            previous_names << name unless previous_names.include?(name)
          end
        end
      end
    end
  end
end
