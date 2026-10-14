# frozen_string_literal: true

require_relative '../../transformers/base_transformer'

module Ammitto
  module Sources
    module Ca
      # Transformer converts Canada source models to the harmonized
      # Ammitto ontology models.
      #
      # @example Transforming a CA record
      #   transformer = Ammitto::Sources::Ca::Transformer.new
      #   result = transformer.transform(record)
      #   entity = result[:entity]    # PersonEntity or OrganizationEntity
      #   entry = result[:entry]      # SanctionEntry
      #
      class Transformer < Ammitto::Transformers::BaseTransformer
        # Mapping of Canadian sanctions programs to regime codes
        REGIME_MAPPING = {
          'SEMA' => { code: 'CA_SEMA', name: 'Special Economic Measures Act' },
          'JVCFOA' => { code: 'CA_JVCFOA', name: 'Justice for Victims of Corrupt Foreign Officials Act' },
          'RUSSIA' => { code: 'RUSSIA', name: 'Russia/Ukraine' },
          'IRAN' => { code: 'IRAN', name: 'Iran' },
          'DPRK' => { code: 'DPRK', name: "Democratic People's Republic of Korea" },
          'MYANMAR' => { code: 'MYANMAR', name: 'Myanmar' },
          'SYRIA' => { code: 'SYRIA', name: 'Syria' },
          'BELARUS' => { code: 'BELARUS', name: 'Belarus' },
          'UKRAINE' => { code: 'UKRAINE', name: 'Ukraine' }
        }.freeze

        def initialize
          super(:ca)
        end

        # Transform a CA Record to ontology models
        # @param record [Ammitto::Sources::Ca::Record]
        # @return [Hash] { entity: Entity, entry: SanctionEntry }
        def transform(record)
          if record.individual?
            transform_individual(record)
          elsif record.vessel?
            transform_vessel(record)
          else
            transform_organization(record)
          end
        end

        canonical_entrypoints :transform

        private

        def transform_individual(record)
          entity = build_model(Ammitto::PersonEntity,
                               id: generate_entity_id(record.generate_id),
                               entity_type: 'person',
                               names: transform_names(record),
                               birth_info: transform_birth_info(record),
                               title: record.english_title_or_ship_type,
                               remarks: build_remarks(record))

          entry = create_entry(record, entity.id)
          link_entry(entity, entry)

          { entity: entity, entry: entry }
        end

        def transform_vessel(record)
          entity = build_model(Ammitto::VesselEntity,
                               id: generate_entity_id(record.generate_id),
                               entity_type: 'vessel',
                               names: transform_names(record),
                               imo_number: record.imo_number,
                               vessel_type: record.english_title_or_ship_type,
                               build_year: build_year(record),
                               remarks: build_remarks(record))

          entry = create_entry(record, entity.id)
          link_entry(entity, entry)

          { entity: entity, entry: entry }
        end

        def transform_organization(record)
          entity = build_model(Ammitto::OrganizationEntity,
                               id: generate_entity_id(record.generate_id),
                               entity_type: 'organization',
                               names: transform_names(record),
                               remarks: build_remarks(record))

          entry = create_entry(record, entity.id)
          link_entry(entity, entry)

          { entity: entity, entry: entry }
        end

        def transform_names(record)
          names = []

          if record.full_name && !record.full_name.strip.empty?
            names << create_name_variant(
              full_name: record.full_name.strip,
              first_name: record.given_name&.strip,
              last_name: record.last_name,
              is_primary: true
            )
          end

          record.alias_names.each do |alias_name|
            next if names.any? { |name| name.full_name == alias_name }

            names << create_name_variant(full_name: alias_name)
          end

          names
        end

        # A value that offers alternatives ("1972-08-10 or 1972-08-11")
        # states no single birth date, and one that carries no readable
        # year or date (a bare month name, "born in the early 1970s")
        # would publish an empty BirthInfo; both are left in the processed
        # YAML only.
        def transform_birth_info(record)
          dob = record.date_of_birth_or_ship_build_date.to_s.strip
          return [] if dob.empty? || dob.match?(/\sor\s/i)

          year = without_circa_marker(dob).to_s[/\A(\d{4})-\d{2}\z/, 1]
          birth = create_birth_info(date: dob, year: year, circa: circa_string?(dob))
          readable = [birth.date, birth.year, birth.date_range_from,
                      birth.year_range_from, birth.year_range_to]
          readable.any? ? [birth] : []
        end

        # A vessel's build date is stated as a year.
        def build_year(record)
          year = record.date_of_birth_or_ship_build_date.to_s.strip
          Integer(year, 10) if year.match?(/\A\d{4}\z/)
        end

        def create_entry(record, entity_id)
          build_model(Ammitto::SanctionEntry,
                      id: generate_entry_id(record.generate_id),
                      entity_id: entity_id,
                      authority: authority,
                      regime: transform_regime(record.country),
                      effects: create_default_effects,
                      status: 'active',
                      reference_number: record.generate_id,
                      remarks: "Schedule: #{record.schedule}, Item: #{record.item}",
                      raw_source_data: create_raw_source_data(
                        source_format: 'xml',
                        source_specific_fields: {
                          'ca:country' => record.country,
                          'ca:schedule' => record.schedule,
                          'ca:item' => record.item,
                          'ca:date_of_listing' => record.date_of_listing
                        }
                      ))
        end

        def transform_regime(country)
          return create_regime(code: 'CA_SEMA', name: 'Canada Sanctions') if country.nil?

          info = REGIME_MAPPING[country.upcase] || { code: "CA_#{country.upcase}", name: country }
          create_regime(code: info[:code], name: info[:name])
        end

        def create_default_effects
          [
            create_effect(effect_type: 'asset_freeze', scope: 'full')
          ]
        end

        def build_remarks(record)
          parts = []
          parts << "Country: #{record.country}" if record.country
          parts << "Schedule: #{record.schedule}" if record.schedule
          parts << "Item: #{record.item}" if record.item
          parts << "Date of Listing: #{record.date_of_listing}" if record.date_of_listing
          parts.join('; ')
        end
      end
    end
  end
end

# Backward compatibility alias
Ammitto::Transformers::CaTransformer = Ammitto::Sources::Ca::Transformer
