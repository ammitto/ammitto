# frozen_string_literal: true

# BaseTransformer is loaded by transformers/registry.rb

module Ammitto
  module Sources
    module Nz
      # Transformer for NZ Sanctions data
      #
      class Transformer < Ammitto::Transformers::BaseTransformer
        def initialize
          super(:nz)
        end

        # Transform NZ entity to harmonized model
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
        # @return [PersonEntity, OrganizationEntity, VesselEntity]
        def create_entity(source)
          entity_type = map_entity_type(source)

          case entity_type
          when 'person'
            create_person_entity(source)
          when 'vessel'
            create_vessel_entity(source)
          else
            create_organization_entity(source)
          end
        end

        # Create person entity
        # @param source [Individual] source model
        # @return [PersonEntity]
        def create_person_entity(source)
          Ammitto::PersonEntity.new.tap do |entity|
            entity.id = generate_entity_id(source.unique_identifier || source.reference_number)
            entity.entity_type = 'person'
            entity.names = build_names(source)
            entity.source_references = build_source_references(source)
          end
        end

        # Create organization entity
        # @param source [Entity] source model
        # @return [OrganizationEntity]
        def create_organization_entity(source)
          Ammitto::OrganizationEntity.new.tap do |entity|
            entity.id = generate_entity_id(source.unique_identifier || source.reference_number)
            entity.entity_type = 'organization'
            entity.names = build_names(source)
            entity.source_references = build_source_references(source)
          end
        end

        # Create vessel entity
        # @param source [Ship] source model
        # @return [VesselEntity]
        def create_vessel_entity(source)
          Ammitto::VesselEntity.new.tap do |entity|
            entity.id = generate_entity_id(source.unique_identifier || source.imo_number)
            entity.entity_type = 'vessel'
            entity.names = build_names(source)
            entity.imo_number = source.imo_number
            entity.source_references = build_source_references(source)
          end
        end

        # Build names array
        # @param source [Object] source model
        # @return [Array<NameVariant>]
        def build_names(source)
          names = []

          # Primary name
          primary = case source
                   when Individual
                     [source.first_name, source.middle_names, source.last_name].compact.join(' ')
                   when Ship
                     source.name
                   else
                     source.name
                   end

          if primary
            names << create_name_variant(full_name: primary, is_primary: true)
          end

          names
        end

        # Build source references
        # @param source [Object] source model
        # @return [Array<SourceReference>]
        def build_source_references(source)
          ref_num = source.unique_identifier || source.reference_number

          [Ammitto::SourceReference.new(
            source_code: 'nz',
            reference_number: ref_num,
            fetched_at: Time.now.utc.iso8601
          )]
        end

        # Map entity type
        # @param source [Object] source model
        # @return [String]
        def map_entity_type(source)
          case source
          when Individual
            'person'
          when Ship
            'vessel'
          else
            'organization'
          end
        end

        # Create sanction entry
        # @param source [Object] source model
        # @param entity [Entity] harmonized entity
        # @return [SanctionEntry]
        def create_entry(source, entity)
          Ammitto::SanctionEntry.new.tap do |entry|
            entry.id = generate_entry_id(source.unique_identifier || source.reference_number)
            entry.entity_id = entity.id
            entry.authority = authority
            entry.regime = create_regime
            entry.status = map_status(source.sanction_status)
            entry.effects = build_effects(source)
            entry.period = create_period(source)
          end
        end

        # Create regime
        # @return [SanctionRegime]
        def create_regime
          Ammitto::SanctionRegime.new(
            name: 'New Zealand Russia Sanctions',
            code: 'NZ-RU'
          )
        end

        # Map status
        # @param status [String]
        # @return [String]
        def map_status(status)
          case status&.downcase
          when 'sanctioned'
            'active'
          else
            'active'
          end
        end

        # Build effects
        # @param source [Object] source model
        # @return [Array<SanctionEffect>]
        def build_effects(source)
          effects = []

          if source.travel_ban == 'Yes'
            effects << create_effect(effect_type: 'travel_ban')
          end

          if source.asset_freeze == 'Yes'
            effects << create_effect(effect_type: 'asset_freeze')
          end

          if source.ship_ban == 'Yes'
            effects << create_effect(effect_type: 'vessel_ban')
          end

          if source.aircraft_ban == 'Yes'
            effects << create_effect(effect_type: 'aircraft_ban')
          end

          effects
        end

        # Create period
        # @param source [Object] source model
        # @return [TemporalPeriod]
        def create_period(source)
          Ammitto::TemporalPeriod.new(
            listed_date: parse_date(source.date_of_sanction),
            is_indefinite: true
          )
        end
      end
    end
  end
end
