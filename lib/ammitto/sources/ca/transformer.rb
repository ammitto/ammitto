# frozen_string_literal: true

require_relative '../../transformers/base_transformer'

module Ammitto
  module Sources
    module Ca
      # Transformer converts Canada source models to the harmonized
      # Ammitto ontology models.
      #
      # @example Transforming a CA individual
      #   transformer = Ammitto::Sources::Ca::Transformer.new
      #   result = transformer.transform(individual)
      #   entity = result[:entity]    # PersonEntity
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
          'BELARUS' => { code: 'BELARUS', name: 'Belarus' }
        }.freeze

        def initialize
          super(:ca)
        end

        # Transform a CA Individual to ontology models
        # @param individual [Ammitto::Sources::Ca::Individual]
        # @return [Hash] { entity: PersonEntity, entry: SanctionEntry }
        def transform_individual(individual)
          entity = create_person_entity(individual)
          entry = create_entry_from_individual(individual)

          entity.add_sanction_entry(entry)

          { entity: entity, entry: entry }
        end

        # Transform a CA Entity to ontology models
        # @param entity [Ammitto::Sources::Ca::Entity]
        # @return [Hash] { entity: OrganizationEntity, entry: SanctionEntry }
        def transform_entity(entity)
          ont_entity = create_organization_entity(entity)
          entry = create_entry_from_entity(entity)

          ont_entity.add_sanction_entry(entry)

          { entity: ont_entity, entry: entry }
        end

        # Generic transform method
        # @param source [Object] CA Individual or Entity
        # @return [Hash]
        def transform(source)
          case source
          when Ammitto::Sources::Ca::Individual
            transform_individual(source)
          when Ammitto::Sources::Ca::Entity
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
            birth_info: transform_birth_info(individual),
            identifications: transform_identifications(individual.identifications),
            remarks: build_remarks(individual)
          )
        end

        def create_organization_entity(entity)
          Ammitto::OrganizationEntity.new(
            id: generate_entity_id(entity.id.to_s),
            entity_type: 'organization',
            names: transform_entity_names(entity),
            addresses: transform_addresses(entity.addresses),
            remarks: build_entity_remarks(entity)
          )
        end

        def create_entry_from_individual(individual)
          Ammitto::SanctionEntry.new(
            id: generate_entry_id(individual.id.to_s),
            entity_id: generate_entity_id(individual.id.to_s),
            authority: authority,
            regime: transform_regime(individual.sanctions_program),
            effects: create_default_effects,
            status: 'active',
            reference_number: individual.id.to_s,
            remarks: individual.schedule,
            raw_source_data: create_raw_source_data(
              source_format: 'xml',
              source_specific_fields: {
                'ca:program' => individual.sanctions_program,
                'ca:schedule' => individual.schedule
              }
            )
          )
        end

        def create_entry_from_entity(entity)
          Ammitto::SanctionEntry.new(
            id: generate_entry_id(entity.id.to_s),
            entity_id: generate_entity_id(entity.id.to_s),
            authority: authority,
            regime: transform_regime(entity.sanctions_program),
            effects: create_default_effects,
            status: 'active',
            reference_number: entity.id.to_s,
            remarks: entity.schedule,
            raw_source_data: create_raw_source_data(
              source_format: 'xml',
              source_specific_fields: {
                'ca:program' => entity.sanctions_program,
                'ca:schedule' => entity.schedule
              }
            )
          )
        end

        def transform_names(individual)
          names = []

          if individual.full_name && !individual.full_name.empty?
            names << create_name_variant(
              full_name: individual.full_name,
              first_name: individual.first_name,
              last_name: individual.last_name,
              is_primary: true
            )
          end

          individual.aliases.each do |alias_obj|
            names << create_name_variant(
              full_name: alias_obj.name,
              is_primary: false
            )
          end

          names
        end

        def transform_entity_names(entity)
          names = []

          if entity.name && !entity.name.empty?
            names << create_name_variant(
              full_name: entity.name,
              is_primary: true
            )
          end

          entity.aliases.each do |alias_obj|
            names << create_name_variant(
              full_name: alias_obj.name,
              is_primary: false
            )
          end

          names
        end

        def transform_addresses(addresses)
          addresses.map do |addr|
            create_address(
              street: addr.street,
              city: addr.city,
              state: addr.province,
              country: addr.country,
              postal_code: addr.postal_code
            )
          end
        end

        def transform_birth_info(individual)
          individual.date_of_birth.map do |dob|
            create_birth_info(
              date: parse_date(dob.date)
            )
          end
        end

        def transform_identifications(identifications)
          identifications.map do |id|
            create_identification(
              type: normalize_id_type(id.type),
              number: id.number,
              issuing_country: id.country
            )
          end
        end

        def transform_regime(program)
          return create_regime(code: 'CA_SEMA', name: 'Canada Sanctions') if program.nil?

          info = REGIME_MAPPING[program.upcase] || { code: program.upcase, name: program }
          create_regime(code: info[:code], name: info[:name])
        end

        def create_default_effects
          [
            create_effect(effect_type: 'asset_freeze', scope: 'full')
          ]
        end

        def normalize_id_type(type)
          return 'Other' if type.nil?

          case type.downcase
          when /passport/
            'Passport'
          when /national.*id/, /sin/
            'NationalID'
          when /driver/
            'DriversLicense'
          else
            type.split.map(&:capitalize).join(' ')
          end
        end

        def build_remarks(individual)
          parts = []
          parts << "Program: #{individual.sanctions_program}" if individual.sanctions_program
          parts << "Schedule: #{individual.schedule}" if individual.schedule
          parts.join('; ')
        end

        def build_entity_remarks(entity)
          parts = []
          parts << "Program: #{entity.sanctions_program}" if entity.sanctions_program
          parts << "Schedule: #{entity.schedule}" if entity.schedule
          parts.join('; ')
        end
      end
    end
  end
end

# Backward compatibility alias
Ammitto::Transformers::CaTransformer = Ammitto::Sources::Ca::Transformer
