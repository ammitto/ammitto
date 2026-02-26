# frozen_string_literal: true

require_relative '../../transformers/base_transformer'

module Ammitto
  module Sources
    module EuVessels
      # Transformer converts EU Vessels source models to the harmonized
      # Ammitto ontology models.
      #
      # @example Transforming an EU Vessel
      #   transformer = Ammitto::Sources::EuVessels::Transformer.new
      #   result = transformer.transform(vessel)
      #   entity = result[:entity]    # VesselEntity
      #   entry = result[:entry]      # SanctionEntry
      #
      class Transformer < Ammitto::Transformers::BaseTransformer
        def initialize
          super(:eu_vessels)
        end

        # Transform an EU Vessel to ontology models
        # @param vessel [Ammitto::Sources::EuVessels::Vessel] the vessel
        # @return [Hash] { entity: Entity, entry: SanctionEntry }
        def transform(vessel)
          entity = create_entity(vessel)
          entry = create_entry(vessel, entity)

          {
            entity: entity,
            entry: entry
          }
        end

        private

        # Create harmonized vessel entity
        # @param vessel [Ammitto::Sources::EuVessels::Vessel]
        # @return [VesselEntity]
        def create_entity(vessel)
          Ammitto::VesselEntity.new.tap do |entity|
            entity.id = generate_entity_id(vessel.imo_number)
            entity.entity_type = 'vessel'
            entity.names = build_names(vessel)
            entity.imo_number = vessel.imo_number
            entity.source_references = build_source_references(vessel)
          end
        end

        # Build names array
        # @param vessel [Ammitto::Sources::EuVessels::Vessel]
        # @return [Array<NameVariant>]
        def build_names(vessel)
          names = []

          names << create_name_variant(full_name: vessel.vessel_name, is_primary: true) if vessel.vessel_name

          names
        end

        # Build source references
        # @param vessel [Ammitto::Sources::EuVessels::Vessel]
        # @return [Array<SourceReference>]
        def build_source_references(vessel)
          [Ammitto::SourceReference.new(
            source_code: 'eu_vessels',
            reference_number: vessel.imo_number,
            fetched_at: Time.now.utc.iso8601
          )]
        end

        # Create sanction entry
        # @param vessel [Ammitto::Sources::EuVessels::Vessel]
        # @param entity [VesselEntity] harmonized entity
        # @return [SanctionEntry]
        def create_entry(vessel, entity)
          Ammitto::SanctionEntry.new.tap do |entry|
            entry.id = generate_entry_id(vessel.imo_number)
            entry.entity_id = entity.id
            entry.authority = authority
            entry.regime = create_regime
            entry.status = 'active'
            entry.effects = build_effects
            entry.period = create_period(vessel)
          end
        end

        # Create regime
        # @return [SanctionRegime]
        def create_regime
          Ammitto::SanctionRegime.new(
            name: 'EU Sanctions Regime',
            code: 'EU'
          )
        end

        # Build effects
        # @return [Array<SanctionEffect>]
        def build_effects
          [
            create_effect(effect_type: 'asset_freeze'),
            create_effect(effect_type: 'transport_sanction')
          ]
        end

        # Create period
        # @param vessel [Ammitto::Sources::EuVessels::Vessel]
        # @return [TemporalPeriod]
        def create_period(vessel)
          Ammitto::TemporalPeriod.new(
            listed_date: vessel.date_of_application,
            is_indefinite: true
          )
        end
      end
    end
  end
end
