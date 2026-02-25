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
          else
            transform_organization(record)
          end
        end

        private

        def transform_individual(record)
          entity = Ammitto::PersonEntity.new(
            id: generate_entity_id(record.generate_id),
            entity_type: 'person',
            names: transform_names(record),
            remarks: build_remarks(record)
          )

          entry = create_entry(record, entity.id)
          entity.add_sanction_entry(entry)

          { entity: entity, entry: entry }
        end

        def transform_organization(record)
          entity = Ammitto::OrganizationEntity.new(
            id: generate_entity_id(record.generate_id),
            entity_type: 'organization',
            names: transform_names(record),
            remarks: build_remarks(record)
          )

          entry = create_entry(record, entity.id)
          entity.add_sanction_entry(entry)

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

          names
        end

        def create_entry(record, entity_id)
          Ammitto::SanctionEntry.new(
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
            )
          )
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
