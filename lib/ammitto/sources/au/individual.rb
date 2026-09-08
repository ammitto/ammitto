# frozen_string_literal: true

require_relative 'base_entity'
require_relative 'flexible_date'
require_relative 'location'

module Ammitto
  module Sources
    module Au
      # The Australian sanctions ontology as a whole, how the denormalized
      # CSV maps onto these objects and what the regimes and effects mean,
      # is in lib/ammitto/sources/au.rb.
      # Sanctioned individual (natural person)
      class Individual < BaseEntity
        attribute :entity_type, :string, default: 'person'
        attribute :dates_of_birth, FlexibleDate, collection: true
        attribute :places_of_birth, Location, collection: true
        attribute :citizenships, :string, collection: true

        yaml do
          map 'reference', to: :reference
          map 'entity_type', to: :entity_type
          map 'names', to: :names
          map 'address', to: :address
          map 'additional_info', to: :additional_info
          map 'sanction', to: :sanction
          map 'dates_of_birth', to: :dates_of_birth
          map 'places_of_birth', to: :places_of_birth
          map 'citizenships', to: :citizenships
        end

        def birth_years
          dates_of_birth.map(&:year).compact.uniq
        end

        def birth_countries
          places_of_birth.map(&:country).compact.uniq
        end

        def merge_row(row)
          super

          # Parse dates of birth (comma-separated, can have multiple)
          dob_str = row['Date of Birth']
          if dob_str && !dob_str.empty?
            dob_str.split(',').map(&:strip).each do |date_str|
              date = FlexibleDate.parse(date_str)
              dates_of_birth << date if date && dates_of_birth.none? { |d| d.raw_value == date.raw_value }
            end
          end

          # Parse places of birth (comma-separated)
          pob_str = row['Place of Birth']
          if pob_str && !pob_str.empty?
            pob_str.split(',').map(&:strip).each do |loc_str|
              next if loc_str.empty?

              loc = Location.parse(loc_str)
              places_of_birth << loc if loc && places_of_birth.none? { |p| p.raw_value == loc.raw_value }
            end
          end

          # Parse citizenships. DFAT separates them with a semicolon, not a
          # comma: of 6304 non-empty cells, 389 carry ';' and 79 carry ','
          # inside a single country name. "Congo, Democratic Republic of
          # the;Rwanda" is both at once, so splitting on ',' tore one country
          # into two that do not exist
          cit_str = row['Citizenship']
          return unless cit_str && !cit_str.empty?

          cit_str.split(';').map(&:strip).reject(&:empty?).each do |cit|
            citizenships << cit unless citizenships.include?(cit)
          end
        end

        def self.from_csv_row(row)
          entity = new(
            reference: parse_base_reference(row['Reference']),
            entity_type: 'person',
            names: [],
            address: row['Address'],
            additional_info: row['Additional Information'],
            sanction: nil,
            dates_of_birth: [],
            places_of_birth: [],
            citizenships: []
          )
          entity.merge_row(row)
          entity
        end
      end
    end
  end
end
