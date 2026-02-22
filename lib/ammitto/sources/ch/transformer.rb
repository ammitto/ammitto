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

        def transform_individual(individual)
          entity = create_person_entity(individual)
          entry = create_entry(individual, entity.id)

          entity.add_sanction_entry(entry)

          { entity: entity, entry: entry }
        end

        def transform_entity(entity_obj)
          entity = create_organization_entity(entity_obj)
          entry = create_entry(entity_obj, entity.id)

          entity.add_sanction_entry(entry)

          { entity: entity, entry: entry }
        end

        def transform(source)
          case source
          when Ammitto::Sources::Ch::Individual
            transform_individual(source)
          when Ammitto::Sources::Ch::Entity
            transform_entity(source)
          else
            raise ArgumentError, "Unknown source type: #{source.class}"
          end
        end

        private

        def create_person_entity(individual)
          Ammitto::PersonEntity.new(
            id: generate_entity_id(individual.id.to_s),
            entity_type: 'person',
            names: transform_names(individual),
            addresses: transform_addresses(individual.addresses),
            birth_info: [create_birth_info(date: parse_date(individual.date_of_birth))],
            identifications: transform_identifications(individual.identifications),
            remarks: individual.sanctions_program
          )
        end

        def create_organization_entity(entity_obj)
          Ammitto::OrganizationEntity.new(
            id: generate_entity_id(entity_obj.id.to_s),
            entity_type: 'organization',
            names: [create_name_variant(full_name: entity_obj.name, is_primary: true)],
            addresses: transform_addresses(entity_obj.addresses),
            remarks: entity_obj.sanctions_program
          )
        end

        def create_entry(source, entity_id)
          Ammitto::SanctionEntry.new(
            id: generate_entry_id(source.id.to_s),
            entity_id: entity_id,
            authority: authority,
            regime: create_regime(code: 'CH_SECO', name: source.sanctions_program || 'Switzerland Sanctions'),
            effects: [create_effect(effect_type: 'asset_freeze', scope: 'full')],
            status: 'active',
            reference_number: source.id.to_s,
            raw_source_data: create_raw_source_data(
              source_format: 'xml',
              source_specific_fields: { 'ch:program' => source.sanctions_program }
            )
          )
        end

        def transform_names(individual)
          names = [create_name_variant(full_name: individual.full_name, is_primary: true)]
          individual.alias_names.each do |a|
            names << create_name_variant(full_name: a.name, is_primary: false)
          end
          names
        end

        def transform_addresses(addresses)
          addresses.map do |a|
            create_address(street: a.street, city: a.city, country: a.country, postal_code: a.postal_code)
          end
        end

        def transform_identifications(ids)
          ids.map do |i|
            create_identification(type: i.type, number: i.number, issuing_country: i.country)
          end
        end
      end
    end
  end
end

# Backward compatibility alias
Ammitto::Transformers::ChTransformer = Ammitto::Sources::Ch::Transformer
