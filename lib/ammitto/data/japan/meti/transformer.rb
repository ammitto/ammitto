# frozen_string_literal: true

require_relative '../../../transformers/base_transformer'
require_relative 'entity'
require_relative 'foreign_user_list'

module Ammitto
  module Data
    module Japan
      module METI
        # Transformer converts METI Foreign User List entities to harmonized ontology models
        #
        # The METI Foreign User List is primarily for export control purposes,
        # not financial sanctions. It lists entities that may be involved in
        # WMD proliferation activities.
        #
        # @example Transforming an entity
        #   transformer = Ammitto::Data::Japan::METI::Transformer.new
        #   result = transformer.transform(meti_entity)
        #   entity = result[:entity]    # OrganizationEntity
        #   entry = result[:entry]      # SanctionEntry
        #
        class Transformer < Ammitto::Transformers::BaseTransformer
          # Initialize the transformer
          def initialize
            super(:jp_meti, list_type: 'foreign-user-list')
          end

          # Transform a METI Entity to ontology models
          #
          # @param source [Ammitto::Data::Japan::METI::Entity] the entity
          # @return [Hash] { entity: OrganizationEntity, entry: SanctionEntry }
          #
          def transform(source)
            entity = create_organization_entity(source)
            entry = create_entry(source, entity)

            {
              entity: entity,
              entry: entry
            }
          end

          private

          # Create harmonized organization entity
          #
          # @param source [Ammitto::Data::Japan::METI::Entity]
          # @return [Ammitto::OrganizationEntity]
          #
          def create_organization_entity(source)
            Ammitto::OrganizationEntity.new.tap do |entity|
              entity.id = generate_entity_id(source.reference_number)
              entity.entity_type = 'organization'
              entity.names = build_names(source)
              entity.addresses = build_addresses(source)
              entity.source_references = build_source_references(source)
              entity.remarks = build_remarks(source)
            end
          end

          # Build names array
          #
          # @param source [Ammitto::Data::Japan::METI::Entity]
          # @return [Array<Ammitto::NameVariant>]
          #
          def build_names(source)
            names = []

            # English name (primary)
            if source.name_en
              names << create_name_variant(
                full_name: source.name_en,
                is_primary: true,
                script: 'Latn'
              )
            end

            # Japanese name
            if source.name_ja
              names << create_name_variant(
                full_name: source.name_ja,
                is_primary: source.name_en.nil?,
                script: 'Jpan'
              )
            end

            # Aliases
            source.aliases.each do |alias_name|
              script = alias_name.match?(/[\p{Hiragana}\p{Katakana}\p{Han}]/) ? 'Jpan' : 'Latn'
              names << create_name_variant(
                full_name: alias_name,
                is_primary: false,
                script: script
              )
            end

            names
          end

          # Build addresses array
          #
          # @param source [Ammitto::Data::Japan::METI::Entity]
          # @return [Array<Ammitto::Address>]
          #
          def build_addresses(source)
            return [] unless source.country_code

            # Create a minimal address with country information
            country_name = source.country_en || source.country_ja
            return [] unless country_name

            [create_address(country: country_name, country_iso_code: source.country_code)]
          end

          # Build source references
          #
          # @param source [Ammitto::Data::Japan::METI::Entity]
          # @return [Array<Ammitto::SourceReference>]
          #
          def build_source_references(source)
            ref = Ammitto::SourceReference.new(
              source_code: 'jp_meti',
              reference_number: source.reference_number,
              fetched_at: Time.now.utc.iso8601
            )

            # Add source URL if available
            ref.url = source.source_url if source.respond_to?(:source_url) && source.source_url

            [ref]
          end

          # Build remarks from WMD types
          #
          # @param source [Ammitto::Data::Japan::METI::Entity]
          # @return [String, nil]
          #
          def build_remarks(source)
            return nil if source.wmd_types.empty?

            wmd_names = source.wmd_descriptions.map do |desc|
              "#{desc[:en]} (#{desc[:ja]})"
            end

            "WMD concerns: #{wmd_names.join(', ')}"
          end

          # Create sanction entry
          #
          # @param source [Ammitto::Data::Japan::METI::Entity]
          # @param entity [Ammitto::OrganizationEntity] harmonized entity
          # @return [Ammitto::SanctionEntry]
          #
          def create_entry(source, entity)
            Ammitto::SanctionEntry.new.tap do |entry|
              entry.id = generate_entry_id(source.reference_number)
              entry.entity_id = entity.id
              entry.authority = authority
              entry.regime = create_regime
              entry.status = 'active'
              entry.effects = build_effects
              entry.period = create_period(source)
              entry.reasons = build_reasons(source)
              entry.remarks = 'METI Foreign User List - Export Control'
            end
          end

          # Create regime
          #
          # @return [Ammitto::SanctionRegime]
          #
          def create_regime
            Ammitto::SanctionRegime.new(
              name: 'Japan METI Foreign User List',
              code: 'JP-METI-FUL'
            )
          end

          # Build effects
          #
          # @return [Array<Ammitto::SanctionEffect>]
          #
          def build_effects
            # METI Foreign User List is for export control
            [
              create_effect(
                effect_type: 'export_restriction',
                description: 'Subject to export license requirements under FEFTA'
              )
            ]
          end

          # Build reasons from WMD types
          #
          # @param source [Ammitto::Data::Japan::METI::Entity]
          # @return [Array<Ammitto::SanctionReason>]
          #
          def build_reasons(source)
            return [] if source.wmd_types.empty?

            source.wmd_descriptions.map do |desc|
              create_reason(
                category: 'wmd_proliferation',
                description: "Involved in development or proliferation of #{desc[:en].downcase}"
              )
            end
          end

          # Create period
          #
          # @param source [Ammitto::Data::Japan::METI::Entity]
          # @return [Ammitto::TemporalPeriod]
          #
          def create_period(source)
            period = Ammitto::TemporalPeriod.new(is_indefinite: true)

            period.listed_date = source.list_date if source.list_date

            period
          end
        end
      end
    end
  end
end
