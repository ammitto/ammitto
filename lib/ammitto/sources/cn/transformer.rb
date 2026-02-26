# frozen_string_literal: true

require_relative '../../transformers/base_transformer'

module Ammitto
  module Sources
    module Cn
      # Transformer converts China (MOFCOM/MFA) source models to the harmonized
      # Ammitto ontology models.
      #
      # China has multiple list types:
      # - Unreliable Entity List (不可靠实体清单) - MOFCOM
      # - Anti-Sanctions List (反制裁清单) - MFA
      # - Export Control List (出口管制管控名单) - MOFCOM
      #
      # Data is published as HTML announcements, not structured XML/JSON.
      #
      # @example Transforming a CN entity
      #   transformer = Ammitto::Sources::Cn::Transformer.new
      #   result = transformer.transform(entity)
      #   entity = result[:entity]    # PersonEntity or OrganizationEntity
      #   entry = result[:entry]      # SanctionEntry
      #
      class Transformer < Ammitto::Transformers::BaseTransformer
        # Mapping of Chinese list types to regime codes
        LIST_TYPE_MAPPING = {
          'unreliable_entity' => {
            code: 'CN_UNRELIABLE_ENTITY',
            name: '不可靠实体清单 (Unreliable Entity List)',
            authority: 'MOFCOM'
          },
          'anti_sanctions' => {
            code: 'CN_ANTI_SANCTIONS',
            name: '反制裁清单 (Anti-Sanctions List)',
            authority: 'MFA'
          },
          'export_control' => {
            code: 'CN_EXPORT_CONTROL',
            name: '出口管制管控名单 (Export Control List)',
            authority: 'MOFCOM'
          }
        }.freeze

        def initialize
          super(:cn)
        end

        # Transform a CN SanctionedEntity to ontology models
        # @param source_entity [Ammitto::Sources::Cn::SanctionedEntity]
        # @return [Hash] { entity: Entity, entry: SanctionEntry }
        def transform(source_entity)
          if source_entity.person?
            transform_person(source_entity)
          else
            transform_organization(source_entity)
          end
        end

        # Transform all entities from an announcement
        # @param announcement [Ammitto::Sources::Cn::Announcement]
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
          base = source_entity.announcement_number || 'CN'
          name_ref = source_entity.english_name || source_entity.chinese_name
          "#{base}-#{sanitize_id(name_ref.to_s[0..30])}"
        end

        def transform_names(source_entity)
          names = []

          # Primary name (English if available, otherwise Chinese)
          if source_entity.english_name && !source_entity.english_name.empty?
            names << create_name_variant(
              full_name: source_entity.english_name,
              script: 'Latn',
              is_primary: true
            )
          end

          if source_entity.chinese_name && !source_entity.chinese_name.empty?
            names << create_name_variant(
              full_name: source_entity.chinese_name,
              script: 'Hani',
              is_primary: source_entity.english_name.nil? || source_entity.english_name.empty?
            )
          end

          names
        end

        def create_entry(source_entity, entity_id)
          list_info = LIST_TYPE_MAPPING[source_entity.list_type] || {
            code: source_entity.list_type.to_s.upcase,
            name: source_entity.list_type,
            authority: 'MOFCOM'
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
                'cn:list_type' => source_entity.list_type,
                'cn:announcement_number' => source_entity.announcement_number,
                'cn:announcement_date' => source_entity.announcement_date,
                'cn:chinese_name' => source_entity.chinese_name,
                'cn:legal_basis' => source_entity.legal_basis,
                'cn:issuing_authority' => list_info[:authority]
              }
            )
          )
        end

        def transform_effects(measures)
          return [create_effect(effect_type: 'sectoral_sanction', scope: 'full')] if measures.nil? || measures.empty?

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
          when /冻结.*财产/, /asset.*freeze/i
            'asset_freeze'
          when /禁止.*签证/, /禁止.*入境/, /entry.*ban/i, /visa/i
            'entry_ban'
          when /禁止.*交易/, /transaction.*ban/i
            'transaction_ban'
          when /禁止.*进出口/, /import.*export/i
            'trade_restriction'
          when /禁止.*投资/, /investment.*ban/i
            'investment_ban'
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
            language: 'zh-CN'
          )
        end

        def build_remarks(source_entity)
          parts = []
          parts << "List: #{source_entity.list_type}" if source_entity.list_type
          parts << "Reason: #{source_entity.reason}" if source_entity.reason
          parts << "Title: #{source_entity.title}" if source_entity.title
          parts << "Gender: #{source_entity.gender}" if source_entity.gender
          parts.join('; ')
        end
      end
    end
  end
end

# Backward compatibility alias
Ammitto::Transformers::CnTransformer = Ammitto::Sources::Cn::Transformer
