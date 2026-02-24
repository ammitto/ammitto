# frozen_string_literal: true

require_relative '../../transformers/base_transformer'

module Ammitto
  module Sources
    module UnVessels
      # Transformer converts UN Designated Vessels source models to the
      # harmonized Ammitto ontology models.
      #
      # @example Transforming a UN Vessel
      #   transformer = Ammitto::Sources::UnVessels::Transformer.new
      #   result = transformer.transform(vessel)
      #   entity = result[:entity]    # VesselEntity
      #   entry = result[:entry]      # SanctionEntry
      #
      class Transformer < Ammitto::Transformers::BaseTransformer
        def initialize
          super(:un_vessels)
        end

        # Transform a UN Vessel to ontology models
        # @param vessel [Ammitto::Sources::UnVessels::Vessel] the vessel
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
        # @param vessel [Ammitto::Sources::UnVessels::Vessel]
        # @return [VesselEntity]
        def create_entity(vessel)
          Ammitto::VesselEntity.new.tap do |entity|
            entity.id = generate_entity_id(vessel.imo_number)
            entity.entity_type = 'vessel'
            entity.names = build_names(vessel)
            entity.imo_number = vessel.imo_number
            entity.flag_state = vessel.flag_state
            entity.build_year = vessel.build_year
            entity.tonnage = vessel.tonnage
            entity.source_references = build_source_references(vessel)
          end
        end

        # Build names array
        # @param vessel [Ammitto::Sources::UnVessels::Vessel]
        # @return [Array<NameVariant>]
        def build_names(vessel)
          names = []

          # Primary vessel name
          if vessel.vessel_name
            names << create_name_variant(full_name: vessel.vessel_name, is_primary: true)
          end

          # Previous names as aliases
          vessel.previous_names.each do |prev_name|
            names << create_name_variant(full_name: prev_name, is_primary: false)
          end

          names
        end

        # Build source references
        # @param vessel [Ammitto::Sources::UnVessels::Vessel]
        # @return [Array<SourceReference>]
        def build_source_references(vessel)
          ref = Ammitto::SourceReference.new(
            source_code: 'un_vessels',
            reference_number: vessel.imo_number,
            fetched_at: Time.now.utc.iso8601
          )
          ref.resolution = vessel.resolution if vessel.resolution
          [ref]
        end

        # Create sanction entry
        # @param vessel [Ammitto::Sources::UnVessels::Vessel]
        # @param entity [VesselEntity] harmonized entity
        # @return [SanctionEntry]
        def create_entry(vessel, entity)
          Ammitto::SanctionEntry.new.tap do |entry|
            entry.id = generate_entry_id(vessel.imo_number)
            entry.entity_id = entity.id
            entry.authority = authority
            entry.regime = create_regime(vessel)
            entry.status = 'active'
            entry.effects = build_effects
            entry.period = create_period(vessel)
          end
        end

        # Create regime based on UN resolution
        # @param vessel [Ammitto::Sources::UnVessels::Vessel]
        # @return [SanctionRegime]
        def create_regime(vessel)
          resolution = vessel.resolution || 'UN Security Council'

          code = case resolution
                 when /1718/i then 'UN-1718'        # DPRK
                 when /1737|2231/i then 'UN-2231'   # Iran
                 when /1970|1973/i then 'UN-1970'   # Libya
                 else 'UN'
                 end

          Ammitto::SanctionRegime.new(
            name: "UN Security Council - #{resolution}",
            code: code
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
        # @param vessel [Ammitto::Sources::UnVessels::Vessel]
        # @return [TemporalPeriod]
        def create_period(vessel)
          Ammitto::TemporalPeriod.new(
            listed_date: vessel.designation_date,
            is_indefinite: true
          )
        end
      end
    end
  end
end
