# frozen_string_literal: true

require_relative '../../transformers/base_transformer'

module Ammitto
  module Sources
    module Jp
      # Transformer converts Japan End-User List source models to the
      # harmonized Ammitto ontology models.
      #
      # Note: Japan's End-User List is primarily for export control purposes,
      # not financial sanctions. It lists entities that may be involved in
      # WMD proliferation activities.
      #
      # @example Transforming a Japan entity
      #   transformer = Ammitto::Sources::Jp::Transformer.new
      #   result = transformer.transform(entity)
      #   entity = result[:entity]    # PersonEntity or OrganizationEntity
      #   entry = result[:entry]      # SanctionEntry
      #
      class Transformer < Ammitto::Transformers::BaseTransformer
        def initialize
          super(:jp)
        end

        # Transform a Japan Entity to ontology models
        # @param source [Ammitto::Sources::Jp::Entity] the entity
        # @return [Hash] { entity: Entity, entry: SanctionEntry }
        def transform(source)
          entity = create_entity(source)
          entry = create_entry(source, entity)

          {
            entity: entity,
            entry: entry
          }
        end

        private

        # Create harmonized entity
        # @param source [Ammitto::Sources::Jp::Entity]
        # @return [PersonEntity, OrganizationEntity]
        def create_entity(source)
          case source.entity_type
          when 'person'
            create_person_entity(source)
          else
            create_organization_entity(source)
          end
        end

        # Create person entity
        # @param source [Ammitto::Sources::Jp::Entity]
        # @return [PersonEntity]
        def create_person_entity(source)
          Ammitto::PersonEntity.new.tap do |entity|
            entity.id = generate_entity_id(source.reference_number)
            entity.entity_type = 'person'
            entity.names = build_names(source)
            entity.source_references = build_source_references(source)
            entity.remarks = source.remarks
          end
        end

        # Create organization entity
        # @param source [Ammitto::Sources::Jp::Entity]
        # @return [OrganizationEntity]
        def create_organization_entity(source)
          Ammitto::OrganizationEntity.new.tap do |entity|
            entity.id = generate_entity_id(source.reference_number)
            entity.entity_type = 'organization'
            entity.names = build_names(source)
            entity.addresses = build_addresses(source)
            entity.source_references = build_source_references(source)
            entity.remarks = source.remarks
          end
        end

        # Build names array
        # @param source [Ammitto::Sources::Jp::Entity]
        # @return [Array<NameVariant>]
        def build_names(source)
          names = []

          # English name (primary)
          if source.name
            names << create_name_variant(full_name: source.name, is_primary: true, script: 'Latn')
          end

          # Japanese name
          if source.name_ja
            names << create_name_variant(full_name: source.name_ja, is_primary: false, script: 'Jpan')
          end

          names
        end

        # Build addresses array
        # @param source [Ammitto::Sources::Jp::Entity]
        # @return [Array<Address>]
        def build_addresses(source)
          return [] if source.addresses.nil? || source.addresses.empty?

          source.addresses.map do |addr|
            create_address(street: addr)
          end
        end

        # Build source references
        # @param source [Ammitto::Sources::Jp::Entity]
        # @return [Array<SourceReference>]
        def build_source_references(source)
          [Ammitto::SourceReference.new(
            source_code: 'jp',
            reference_number: source.reference_number,
            fetched_at: Time.now.utc.iso8601
          )]
        end

        # Create sanction entry
        # @param source [Ammitto::Sources::Jp::Entity]
        # @param entity [Entity] harmonized entity
        # @return [SanctionEntry]
        def create_entry(source, entity)
          Ammitto::SanctionEntry.new.tap do |entry|
            entry.id = generate_entry_id(source.reference_number)
            entry.entity_id = entity.id
            entry.authority = authority
            entry.regime = create_regime
            entry.status = 'active'
            entry.effects = build_effects
            entry.period = create_period
            entry.remarks = 'Japan End-User List - Export Control'
          end
        end

        # Create regime
        # @return [SanctionRegime]
        def create_regime
          Ammitto::SanctionRegime.new(
            name: 'Japan End-User List (METI)',
            code: 'JP-EUL'
          )
        end

        # Build effects
        # @return [Array<SanctionEffect>]
        def build_effects
          # Japan End-User List is for export control, not financial sanctions
          [
            create_effect(effect_type: 'export_restriction', description: 'Subject to export license requirements')
          ]
        end

        # Create period
        # @return [TemporalPeriod]
        def create_period
          Ammitto::TemporalPeriod.new(
            is_indefinite: true
          )
        end
      end
    end
  end
end
