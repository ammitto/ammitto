# frozen_string_literal: true

require_relative '../../transformers/base_transformer'
require_relative '../../official_announcement'
require_relative '../../person_entity'
require_relative '../../organization_entity'
require_relative '../../sanction_entry'
require_relative '../../sanction_effect'
require_relative '../../sanction_reason'
require_relative '../../temporal_period'
require_relative '../../authority'
require_relative '../../sanction_regime'
require_relative '../../ontology/sanction/sanction_group'
require_relative '../../ontology/sanction/sanction_period_modification'
require_relative '../../ontology/value_objects/legal_citation'
require_relative '../../ontology/value_objects/localized_string'
require_relative '../../ontology/value_objects/name_variant'

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
      # @example Transforming a CN announcement
      #   transformer = Ammitto::Sources::Cn::Transformer.new
      #   result = transformer.transform_announcement(announcement)
      #   entities = result[:entities]
      #   entries = result[:entries]
      #
      class Transformer < Ammitto::Transformers::BaseTransformer
        # Mapping of Chinese list types to regime codes and list type slugs
        LIST_TYPE_MAPPING = {
          'unreliable_entity' => {
            code: 'CN_UNRELIABLE_ENTITY',
            name: '不可靠实体清单 (Unreliable Entity List)',
            authority: 'MOFCOM',
            list_slug: 'unreliable-entity-list'
          },
          'anti_sanctions' => {
            code: 'CN_ANTI_SANCTIONS',
            name: '反制裁清单 (Anti-Sanctions List)',
            authority: 'MFA',
            list_slug: 'anti-sanction-list'
          },
          'export_control' => {
            code: 'CN_EXPORT_CONTROL',
            name: '出口管制管控名单 (Export Control List)',
            authority: 'MOFCOM',
            list_slug: 'import-export-control-list'
          }
        }.freeze

        def initialize
          super(:cn)
        end

        # Transform an Announcement (YAML format) to all harmonized models
        # @param announcement [Ammitto::Sources::Cn::Announcement]
        # @return [Hash] { entities:, entries:, group:, official_announcement:, legal_citations: }
        def transform_announcement(announcement)
          legal_citations = create_legal_citations(announcement.instruments)
          official_ann = create_official_announcement(announcement.announcement)

          entities = []
          entries = []

          announcement.entities.each do |entity|
            result = transform_entity(entity, announcement, legal_citations)
            entities << result[:entity]
            entries << result[:entry]
          end

          group = nil
          if announcement.multi_entity?
            # Extract title - prefer Chinese title from LocalizedString array
            title = extract_announcement_title(announcement.announcement)

            group = create_sanction_group(
              announcement_id: official_ann&.id,
              announcement_title: title,
              entries: entries,
              entity_count: entities.size,
              effective_date: parse_date(announcement.entities.first&.effective_date),
              effective_time: announcement.entities.first&.effective_time
            )

            # Set group_id on all entries
            entries.each { |e| e.group_id = group.id }
          end

          {
            entities: entities,
            entries: entries,
            group: group,
            official_announcement: official_ann,
            legal_citations: legal_citations
          }
        end

        # Transform a MeasureModification to harmonized models
        # @param modification [Ammitto::Sources::Cn::MeasureModification]
        # @return [Hash] { official_announcement:, modifications:, legal_citations: }
        def transform_modification(modification)
          legal_citations = create_legal_citations(modification.instruments)
          official_ann = create_official_announcement(modification.announcement)

          modifications = modification.modifications.map do |mod|
            create_sanction_period_modification(
              modification: mod,
              announcement_id: official_ann&.id,
              legal_citations: legal_citations
            )
          end

          {
            official_announcement: official_ann,
            modifications: modifications,
            legal_citations: legal_citations
          }
        end

        private

        # Transform a single Entity from the YAML format
        def transform_entity(entity, announcement, legal_citations)
          if entity.person?
            transform_person_entity(entity, announcement, legal_citations)
          else
            transform_org_entity(entity, announcement, legal_citations)
          end
        end

        def transform_person_entity(entity, announcement, legal_citations)
          ref = create_entity_reference(entity, announcement)
          entity_id = generate_entity_id(ref)
          entry = create_entry(entity, announcement, entity_id, legal_citations)

          person = Ammitto::PersonEntity.new(
            id: entity_id,
            entity_type: 'person',
            names: transform_names(entity),
            gender: entity.gender,
            remarks: build_remarks(entity),
            sanction_entry_ids: [entry.id]
          )

          { entity: person, entry: entry }
        end

        def transform_org_entity(entity, announcement, legal_citations)
          ref = create_entity_reference(entity, announcement)
          entity_id = generate_entity_id(ref)
          entry = create_entry(entity, announcement, entity_id, legal_citations)

          org = Ammitto::OrganizationEntity.new(
            id: entity_id,
            entity_type: 'organization',
            names: transform_names(entity),
            remarks: build_remarks(entity),
            sanction_entry_ids: [entry.id]
          )

          { entity: org, entry: entry }
        end

        def create_entity_reference(entity, announcement)
          doc_id = announcement.announcement&.document_id || 'CN'
          name_ref = entity.english_name || entity.chinese_name
          "#{sanitize_id(doc_id)}-#{sanitize_id(name_ref.to_s[0..30])}"
        end

        def transform_names(entity)
          names = []

          if entity.english_name && !entity.english_name.empty?
            names << create_name_variant(
              full_name: entity.english_name,
              script: 'Latn',
              is_primary: true
            )
          end

          if entity.chinese_name && !entity.chinese_name.empty?
            names << create_name_variant(
              full_name: entity.chinese_name,
              script: 'Hani',
              is_primary: entity.english_name.nil? || entity.english_name.empty?
            )
          end

          names
        end

        def create_entry(entity, announcement, entity_id, legal_citations)
          list_info = LIST_TYPE_MAPPING[entity.list_type_code] || {
            code: entity.list_type_code.to_s.upcase,
            name: entity.sanction_list,
            authority: 'MOFCOM',
            list_slug: entity.list_type_code.to_s.gsub('_', '-')
          }

          Ammitto::SanctionEntry.new(
            id: generate_entry_id(
              create_entity_reference(entity, announcement),
              entry_list_type: list_info[:list_slug]
            ),
            entity_id: entity_id,
            authority: authority,
            regime: create_regime(code: list_info[:code], name: list_info[:name]),
            effects: transform_effects(entity.measures),
            reasons: transform_reasons(entity.reason),
            period: create_temporal_period(entity),
            status: 'active',
            reference_number: create_entity_reference(entity, announcement),
            announcement: create_official_announcement(announcement.announcement),
            legal_citations: legal_citations,
            raw_source_data: create_raw_source_data(
              source_format: 'yaml',
              source_specific_fields: {
                'cn:list_type' => entity.list_type_code,
                'cn:sanction_list' => entity.sanction_list,
                'cn:chinese_name' => entity.chinese_name,
                'cn:english_name' => entity.english_name
              }
            )
          )
        end

        def transform_reasons(reasons_data)
          return [] if reasons_data.nil? || reasons_data.empty?

          reasons_data.map do |reason_hash|
            Ammitto::SanctionReason.new(
              category: 'other',
              description: build_localized_strings_from_hash(reason_hash)
            )
          end.compact
        end

        # Build LocalizedString array from a hash with language keys
        # @param hash [Hash] hash with keys like 'zh-Hans', 'en'
        # @return [Array<LocalizedString>]
        def build_localized_strings_from_hash(hash)
          return [] unless hash.is_a?(Hash)

          LANG_MAP.map do |lang, config|
            value = hash[config[:key]]
            next nil if value.nil? || value.to_s.strip.empty?

            Ammitto::Ontology::ValueObjects::LocalizedString.new(
              value: value.to_s.strip,
              language: lang,
              script: config[:script],
              is_primary: config[:is_primary]
            )
          end.compact
        end

        # Language configuration map - single source of truth
        LANG_MAP = {
          'zh' => { key: 'zh-Hans', script: 'Hani', is_primary: true },
          'en' => { key: 'en', script: 'Latn', is_primary: false }
        }.freeze

        def transform_effects(measures)
          return [create_effect(effect_type: 'sectoral_sanction', scope: 'full')] if measures.nil? || measures.empty?

          measures.map do |measure|
            effect_types = measure.type || ['sectoral_sanction']
            create_effect(
              effect_type: effect_types.first,
              scope: 'full',
              description: build_localized_descriptions(measure)
            )
          end
        end

        # Build localized descriptions from Measure using a language map
        def build_localized_descriptions(measure)
          lang_map = {
            'zh' => { getter: :chinese_description, script: 'Hani', is_primary: true },
            'en' => { getter: :english_description, script: 'Latn', is_primary: false }
          }

          lang_map.map do |lang, config|
            value = measure.send(config[:getter])
            next nil if value.nil? || value.empty?

            Ammitto::Ontology::ValueObjects::LocalizedString.new(
              value: value,
              language: lang,
              script: config[:script],
              is_primary: config[:is_primary]
            )
          end.compact
        end

        def create_temporal_period(entity)
          Ammitto::TemporalPeriod.new(
            effective_date: parse_date(entity.effective_date),
            effective_time: entity.effective_time,
            is_indefinite: entity.effective_date.nil?
          )
        end

        def create_official_announcement(announcement_block)
          return nil unless announcement_block

          Ammitto::OfficialAnnouncement.new(
            id: generate_announcement_id(sanitize_id(announcement_block.document_id || 'unknown')),
            title: extract_announcement_title(announcement_block),
            url: announcement_block.url,
            publish_date: parse_date(announcement_block.publish_date),
            publish_time: announcement_block.publish_time,
            document_id: announcement_block.document_id,
            document_type: announcement_block.type,
            signatory: announcement_block.signatory,
            signatory_title: announcement_block.signatory_title,
            publisher: announcement_block.publisher,
            authority: announcement_block.authority,
            content: announcement_block.content,
            language: normalize_language(announcement_block.lang)
          )
        end

        # Normalize language code to standard format
        # @param lang [String, nil] Language code from source data
        # @return [String] Normalized language code (e.g., "zh-CN", "en")
        def normalize_language(lang)
          return 'zh-CN' if lang.nil? || lang.empty?

          # Convert zh-Hans to zh-CN, zh-Hant to zh-TW, etc.
          case lang
          when 'zh-Hans' then 'zh-CN'
          when 'zh-Hant' then 'zh-TW'
          else lang
          end
        end

        def build_remarks(entity)
          parts = []
          parts << "List: #{entity.sanction_list}" if entity.sanction_list
          parts << "Title: #{entity.title&.dig('zh-Hans')}" if entity.title
          parts << "Gender: #{entity.gender}" if entity.gender
          parts.join('; ')
        end

        def create_legal_citations(instruments)
          return [] if instruments.nil? || instruments.empty?

          instruments.map do |instrument|
            # Use ID from source data if available
            # `if instrument.id` guards nil, not blank, and "" is truthy — so
            # a record carrying `id: ""` skipped the fallback and raised
            # MissingLocalIdError out of the sanitizer instead of naming the
            # law. Treat a blank id as an absent one.
            # The law is handed over raw. `sanitize_id` would turn a blank law
            # into DEFAULT_ID, and a record with neither id nor law would then
            # take a shared `.../legal_instrument/cn/unknown` instead of
            # raising — the collapse iri_sanitizer.rb refuses by design.
            # `generate_legal_instrument_id` sanitizes and raises on its own.
            local_id = instrument.id.to_s.strip.sub(%r{^cn/}, '')
            instrument_id = if local_id.empty?
                              generate_legal_instrument_id(instrument.law)
                            else
                              generate_legal_instrument_id(local_id)
                            end
            Ammitto::Ontology::ValueObjects::LegalCitation.new(
              legal_instrument_id: instrument_id,
              articles: instrument.articles || [],
              citation_type: 'legal_basis'
            )
          end
        end

        # Extract title from AnnouncementBlock, handling both string and array formats
        # @param announcement_block [AnnouncementBlock, nil]
        # @return [String, nil]
        def extract_announcement_title(announcement_block)
          return nil unless announcement_block

          # Use the chinese_title method which returns a string
          # Fall back to english_title if no Chinese title
          announcement_block.chinese_title || announcement_block.english_title
        end

        def create_sanction_group(announcement_id:, entries:, entity_count:,
                                  announcement_title: nil, effective_date: nil, effective_time: nil)
          entry_ids = entries.map(&:id)

          Ammitto::Ontology::Sanction::SanctionGroup.new(
            id: generate_group_id(announcement_id),
            announcement_id: announcement_id,
            announcement_title: announcement_title,
            entry_ids: entry_ids,
            entity_count: entity_count,
            effective_date: effective_date,
            effective_time: effective_time,
            notes: "Group of #{entity_count} entities sanctioned together"
          )
        end

        def generate_group_id(announcement_id)
          local_id = announcement_id.to_s.split('/').last
          "https://www.ammitto.org/group/cn/#{local_id}"
        end

        def create_sanction_period_modification(modification:, announcement_id:, legal_citations: [])
          mod_id = generate_modification_id(announcement_id, modification.target_announcement_id)

          Ammitto::Ontology::Sanction::SanctionPeriodModification.new(
            id: mod_id,
            target_type: 'announcement',
            target_announcement_id: modification.target_announcement_id,
            target_announcement_date: parse_date(modification.target_announcement_date),
            action: modification.action,
            effective_date: parse_date(modification.effective_date),
            effective_time: modification.effective_time,
            until_date: parse_date(modification.until_date),
            until_time: modification.until_time,
            duration_days: modification.duration_days,
            announcement_id: announcement_id,
            legal_citations: legal_citations,
            notes: modification.notes,
            status: 'active'
          )
        end

        def generate_modification_id(announcement_id, target_id)
          local_id = announcement_id.to_s.split('/').last
          target_ref = sanitize_id(target_id || 'unknown')
          "https://www.ammitto.org/modification/cn/#{local_id}-#{target_ref}"
        end
      end
    end
  end
end

# Backward compatibility alias
Ammitto::Transformers::CnTransformer = Ammitto::Sources::Cn::Transformer
