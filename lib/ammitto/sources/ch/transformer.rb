# frozen_string_literal: true

require_relative '../../transformers/base_transformer'

module Ammitto
  module Sources
    module Ch
      # Transformer converts Switzerland source models to the harmonized
      # Ammitto ontology models.
      class Transformer < Ammitto::Transformers::BaseTransformer
        def initialize
          super(:ch)
        end

        # Transform a CH Target to ontology models
        # @param target [Ammitto::Sources::Ch::Target]
        # @return [Hash] { entity: Entity, entry: SanctionEntry }
        def transform(target)
          if target.individual
            transform_individual(target)
          elsif target.entity
            transform_entity(target)
          else
            # Minimal data - create entity directly
            transform_from_minimal(target)
          end
        end

        private

        def transform_individual(target)
          individual = target.individual
          identity = individual.identity

          entity = Ammitto::PersonEntity.new(
            id: generate_entity_id(target.ssid),
            entity_type: 'person',
            names: transform_names_from_identity(identity),
            birth_info: transform_birth_info(identity),
            remarks: individual.justification
          )

          entry = create_entry(target, entity.id)
          entity.add_sanction_entry(entry)

          { entity: entity, entry: entry }
        end

        def transform_entity(target)
          entity_obj = target.entity
          identity = entity_obj.identity

          entity = Ammitto::OrganizationEntity.new(
            id: generate_entity_id(target.ssid),
            entity_type: 'organization',
            names: transform_names_from_identity(identity),
            remarks: entity_obj.justification
          )

          entry = create_entry(target, entity.id)
          entity.add_sanction_entry(entry)

          { entity: entity, entry: entry }
        end

        def transform_from_minimal(target)
          entity = Ammitto::OrganizationEntity.new(
            id: generate_entity_id(target.ssid),
            entity_type: 'organization',
            names: [create_name_variant(full_name: "Entity #{target.ssid}", is_primary: true)],
            remarks: "Sanctions Set ID: #{target.sanctions_set_id}"
          )

          entry = create_entry(target, entity.id)
          entity.add_sanction_entry(entry)

          { entity: entity, entry: entry }
        end

        def transform_names_from_identity(identity)
          names = []

          full_name = identity&.full_name
          names << create_name_variant(full_name: full_name, is_primary: true) if full_name && !full_name.empty?

          names
        end

        def transform_birth_info(identity)
          return [] unless identity&.day_month_year

          dmy = identity.day_month_year
          return [] unless dmy.year

          date_str = dmy.to_iso_date
          [create_birth_info(date: parse_date(date_str))]
        end

        def create_entry(target, entity_id)
          Ammitto::SanctionEntry.new(
            id: generate_entry_id(target.ssid),
            entity_id: entity_id,
            authority: authority,
            regime: create_regime(code: 'CH_SECO', name: 'Switzerland SECO Sanctions'),
            effects: [create_effect(effect_type: 'asset_freeze', scope: 'full')],
            status: 'active',
            reference_number: target.ssid,
            raw_source_data: create_raw_source_data(
              source_format: 'xml',
              source_specific_fields: {
                'ch:ssid' => target.ssid,
                'ch:sanctions_set_id' => target.sanctions_set_id
              }
            )
          )
        end
      end
    end
  end
end

# Backward compatibility alias
Ammitto::Transformers::ChTransformer = Ammitto::Sources::Ch::Transformer
