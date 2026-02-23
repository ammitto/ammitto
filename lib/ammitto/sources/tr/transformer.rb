# frozen_string_literal: true

# BaseTransformer is loaded by transformers/registry.rb

module Ammitto
  module Sources
    module Tr
      # Transformer for Turkey Sanctions data
      #
      class Transformer < Ammitto::Transformers::BaseTransformer
        # Transform TR entity to harmonized model
        # @param source [Object] source model
        # @return [Hash] { entity: Entity, entry: SanctionEntry }
        def transform(source)
          entity = create_entity(source)
          entry = create_entry(source, entity)

          { entity: entity, entry: entry }
        end

        private

        # Create harmonized entity
        # @param source [Object] source model
        # @return [PersonEntity, OrganizationEntity]
        def create_entity(source)
          entity_type = map_entity_type(source)

          case entity_type
          when 'person'
            create_person_entity(source)
          else
            create_organization_entity(source)
          end
        end

        # Create person entity
        # @param source [Object] source model
        # @return [PersonEntity]
        def create_person_entity(source)
          Ammitto::PersonEntity.new.tap do |entity|
            entity.id = generate_entity_id(source.reference_number)
            entity.entity_type = 'person'
            entity.names = build_names(source)
            entity.source_references = build_source_references(source)
          end
        end

        # Create organization entity
        # @param source [Object] source model
        # @return [OrganizationEntity]
        def create_organization_entity(source)
          Ammitto::OrganizationEntity.new.tap do |entity|
            entity.id = generate_entity_id(source.reference_number)
            entity.entity_type = 'organization'
            entity.names = build_names(source)
            entity.source_references = build_source_references(source)
          end
        end

        # Build names array
        # @param source [Object] source model
        # @return [Array<NameVariant>]
        def build_names(source)
          names = []

          if source.name
            names << create_name_variant(full_name: source.name, is_primary: true)
          end

          names
        end

        # Build source references
        # @param source [Object] source model
        # @return [Array<SourceReference>]
        def build_source_references(source)
          [Ammitto::SourceReference.new(
            source_code: 'tr',
            reference_number: source.reference_number,
            fetched_at: Time.now.utc.iso8601
          )]
        end

        # Map entity type
        # @param source [Object] source model
        # @return [String]
        def map_entity_type(source)
          source.entity_type&.downcase == 'person' ? 'person' : 'organization'
        end

        # Create sanction entry
        # @param source [Object] source model
        # @param entity [Entity] harmonized entity
        # @return [SanctionEntry]
        def create_entry(source, entity)
          Ammitto::SanctionEntry.new.tap do |entry|
            entry.id = generate_entry_id(source.reference_number)
            entry.entity_id = entity.id
            entry.authority = authority
            entry.regime = create_regime(source.program)
            entry.status = 'active'
            entry.effects = build_effects(source)
            entry.period = create_period(source)
          end
        end

        # Create regime
        # @param program [String] program name
        # @return [SanctionRegime]
        def create_regime(program)
          code = case program
                 when /7262.*3\.A/i then 'TR-D'
                 when /7262/i then 'TR-D'
                 when /6415.*6/i then 'TR-B'
                 when /6415/i then 'TR-C'
                 else 'TR'
                 end

          Ammitto::SanctionRegime.new(
            name: "Turkey #{program || 'Sanctions'}",
            code: code
          )
        end

        # Build effects
        # @param source [Object] source model
        # @return [Array<SanctionEffect>]
        def build_effects(source)
          # Turkey typically imposes asset freeze and entry ban
          [
            create_effect(effect_type: 'asset_freeze'),
            create_effect(effect_type: 'entry_ban')
          ]
        end

        # Create period
        # @param source [Object] source model
        # @return [TemporalPeriod]
        def create_period(source)
          Ammitto::TemporalPeriod.new(
            listed_date: parse_date(source.listed_date),
            is_indefinite: true
          )
        end
      end
    end
  end
end
