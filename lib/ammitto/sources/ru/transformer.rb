# frozen_string_literal: true

require_relative '../../transformers/base_transformer'

module Ammitto
  module Sources
    module Ru
      # Transformer converts Russia (MID/CBR) source models to the harmonized
      # Ammitto ontology models.
      #
      # Russia maintains:
      # 1. Stop-list (Стоп-лист) - Entry bans on foreign persons
      # 2. Central Bank sanctions
      # 3. Government decrees (Постановления)
      #
      # Data is published as HTML announcements from Ministry of Foreign Affairs (MID).
      #
      # @example Transforming a RU entity
      #   transformer = Ammitto::Sources::Ru::Transformer.new
      #   result = transformer.transform(entity)
      #   entity = result[:entity]    # PersonEntity or OrganizationEntity
      #   entry = result[:entry]      # SanctionEntry
      #
      class Transformer < Ammitto::Transformers::BaseTransformer
        # Mapping of Russian list types to regime codes
        LIST_TYPE_MAPPING = {
          'stop_list' => {
            code: 'RU_STOP_LIST',
            name: 'Стоп-лист (Stop-list)',
            description: 'Entry bans on foreign persons'
          },
          'financial_sanctions' => {
            code: 'RU_FINANCIAL',
            name: 'Финансовые санкции (Financial Sanctions)',
            description: 'Central Bank sanctions'
          },
          'government_decree' => {
            code: 'RU_DECREE',
            name: 'Постановления (Government Decrees)',
            description: 'Government sanctions decrees'
          }
        }.freeze

        def initialize
          super(:ru)
        end

        # Transform a RU SanctionedEntity to ontology models
        # @param source_entity [Ammitto::Sources::Ru::SanctionedEntity]
        # @return [Hash] { entity: Entity, entry: SanctionEntry }
        def transform(source_entity)
          if source_entity.person?
            transform_person(source_entity)
          else
            transform_organization(source_entity)
          end
        end

        # Transform all entities from an announcement
        # @param announcement [Ammitto::Sources::Ru::Announcement]
        # @return [Array<Hash>] array of transformation results
        def transform_announcement(announcement)
          announcement.entities.map { |entity| transform(entity) }
        end

        private

        def transform_person(source_entity)
          entity = Ammitto::PersonEntity.new(
            id: generate_entity_id(create_reference(source_entity)),
            entity_type: 'person',
            names: transform_names(source_entity),
            birth_info: [create_birth_info(
              date: parse_date(source_entity.date_of_birth),
              country: source_entity.nationality
            )].compact,
            nationalities: [source_entity.nationality].compact,
            remarks: build_remarks(source_entity)
          )

          entry = create_entry(source_entity, entity.id)
          entity.add_sanction_entry(entry)

          { entity: entity, entry: entry }
        end

        def transform_organization(source_entity)
          entity = Ammitto::OrganizationEntity.new(
            id: generate_entity_id(create_reference(source_entity)),
            entity_type: 'organization',
            names: transform_names(source_entity),
            remarks: build_remarks(source_entity)
          )

          entry = create_entry(source_entity, entity.id)
          entity.add_sanction_entry(entry)

          { entity: entity, entry: entry }
        end

        def create_reference(source_entity)
          # Use announcement number + name as reference
          base = source_entity.announcement_number || 'RU'
          name_ref = source_entity.english_name || source_entity.russian_name
          "#{base}-#{sanitize_id(name_ref.to_s[0..30])}"
        end

        def transform_names(source_entity)
          names = []

          # Russian name (Cyrillic)
          if source_entity.russian_name && !source_entity.russian_name.empty?
            names << create_name_variant(
              full_name: source_entity.russian_name,
              script: 'Cyrl',
              is_primary: source_entity.english_name.nil? || source_entity.english_name.empty?
            )
          end

          # English name (Latin)
          if source_entity.english_name && !source_entity.english_name.empty?
            names << create_name_variant(
              full_name: source_entity.english_name,
              script: 'Latn',
              is_primary: true
            )
          end

          names
        end

        def create_entry(source_entity, entity_id)
          list_info = LIST_TYPE_MAPPING[source_entity.list_type] || {
            code: "RU_#{source_entity.list_type.to_s.upcase}",
            name: source_entity.list_type,
            description: nil
          }

          Ammitto::SanctionEntry.new(
            id: generate_entry_id(create_reference(source_entity)),
            entity_id: entity_id,
            authority: authority,
            regime: create_regime(code: list_info[:code], name: list_info[:name]),
            effects: transform_effects(source_entity.measures),
            status: 'active',
            reference_number: create_reference(source_entity),
            announcement: create_announcement(source_entity),
            raw_source_data: create_raw_source_data(
              source_format: 'html',
              source_specific_fields: {
                'ru:list_type' => source_entity.list_type,
                'ru:announcement_number' => source_entity.announcement_number,
                'ru:announcement_date' => source_entity.announcement_date,
                'ru:russian_name' => source_entity.russian_name,
                'ru:title' => source_entity.title,
                'ru:affiliation' => source_entity.affiliation,
                'ru:country' => source_entity.country,
                'ru:industry' => source_entity.industry
              }
            )
          )
        end

        def transform_effects(measures)
          return [create_effect(effect_type: 'entry_ban', scope: 'full')] if measures.empty?

          measures.map do |measure|
            effect_type = map_measure_to_effect(measure)
            create_effect(
              effect_type: effect_type,
              scope: 'full',
              description: measure
            )
          end
        end

        def map_measure_to_effect(measure)
          case measure
          when /въезд/, /entry.*ban/i, /stop.*list/i
            'entry_ban'
          when /замораживан.*актив/, /asset.*freeze/i, /freeze/i
            'asset_freeze'
          when /ограничен.*финансов/, /financial.*restriction/i
            'financial_restriction'
          when /запрет.*сделок/, /transaction.*ban/i
            'transaction_ban'
          else
            'sectoral_sanction'
          end
        end

        def create_announcement(source_entity)
          return nil unless source_entity.source_url

          Ammitto::OfficialAnnouncement.new(
            title: "Announcement #{source_entity.announcement_number}",
            url: source_entity.source_url,
            published_date: parse_date(source_entity.announcement_date),
            language: 'ru'
          )
        end

        def build_remarks(source_entity)
          parts = []
          parts << "List: #{source_entity.list_type}" if source_entity.list_type
          parts << "Reason: #{source_entity.reason}" if source_entity.reason
          parts << "Title: #{source_entity.title}" if source_entity.title
          parts << "Affiliation: #{source_entity.affiliation}" if source_entity.affiliation
          parts << "Country: #{source_entity.country}" if source_entity.country
          parts << "Industry: #{source_entity.industry}" if source_entity.industry
          parts.join('; ')
        end
      end
    end
  end
end

# Backward compatibility alias
Ammitto::Transformers::RuTransformer = Ammitto::Sources::Ru::Transformer
