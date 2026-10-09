# frozen_string_literal: true

require_relative '../../error'
require_relative '../../transformers/base_transformer'
require_relative '../../logger'
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
        # The sanitizer's sentinel, treated here as "no usable id".
        # `sanitize_id` returns it for an id it cannot build anything
        # from, and also for one that sanitizes to the sentinel itself —
        # a source that writes "unknown". Both are unusable to us.
        UNUSABLE_ID = Ammitto::Utils::IriSanitizer::DEFAULT_ID

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

        # Language configuration map - single source of truth
        LANG_MAP = {
          'zh' => { key: 'zh-Hans', script: 'Hani', is_primary: true },
          'en' => { key: 'en', script: 'Latn', is_primary: false }
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

          references = announcement_references(announcement)
          announcement.entities.each do |entity|
            result = transform_entity(entity, announcement, legal_citations, references.fetch(entity))
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
              # Left unreported: the first entity's period already reported
              # this same value, and one bad cell should count once.
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
        def transform_entity(entity, announcement, legal_citations, ref)
          if entity.person?
            transform_person_entity(entity, announcement, legal_citations, ref)
          else
            transform_org_entity(entity, announcement, legal_citations, ref)
          end
        end

        def transform_person_entity(entity, announcement, legal_citations, ref)
          entity_id = generate_entity_id(ref)
          entry = create_entry(entity, announcement, entity_id, legal_citations, ref)

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

        def transform_org_entity(entity, announcement, legal_citations, ref)
          entity_id = generate_entity_id(ref)
          entry = create_entry(entity, announcement, entity_id, legal_citations, ref)

          org = Ammitto::OrganizationEntity.new(
            id: entity_id,
            entity_type: 'organization',
            names: transform_names(entity),
            remarks: build_remarks(entity),
            sanction_entry_ids: [entry.id]
          )

          { entity: org, entry: entry }
        end

        def cut_reference(doc_id, name)
          "#{doc_id}-#{sanitize_id(name[0..30])}"
        end

        # The readable part of a reference is the name cut at 31 characters,
        # so two long names sharing that prefix in one announcement would
        # meet on one IRI and the exporter would keep only one of them.
        # Parties whose cut references clash take their full name instead;
        # if any two parties still share a reference after that, nothing in
        # the source tells them apart, so each takes a number in notice
        # order and a warning names them for a human to check. Computed once
        # per transform_announcement and passed down, so it holds no state
        # between announcements.
        def announcement_references(announcement)
          doc_id = naming_id(announcement.announcement&.document_id, :document_id)
          names = announcement.entities.map { |e| (e.english_name || e.chinese_name).to_s }
          refs = names.map { |name| cut_reference(doc_id, name) }
          clashing = refs.each_index.group_by { |i| sanitize_id(refs[i]) }.values.select { |g| g.size > 1 }.flatten
          clashing.each { |i| refs[i] = "#{doc_id}-#{sanitize_id(names[i])}" }
          number_identical_references(announcement, names, refs)

          references = {}.compare_by_identity
          announcement.entities.each_with_index { |e, i| references[e] = refs[i] }
          references
        end

        def number_identical_references(announcement, names, refs)
          groups = refs.each_index.group_by { |i| sanitize_id(refs[i]) }
          taken = groups.select { |_, group| group.size == 1 }.keys
          groups.each_value do |group|
            next if group.size == 1

            base = refs[group.first]
            number = 0
            group.each do |i|
              number += 1
              number += 1 while taken.include?(numbered_reference(base, number))
              refs[i] = numbered_reference(base, number)
              taken << refs[i]
            end
            Ammitto::Logger.warn(
              "#{announcement.announcement&.document_id}: parties share one id even after taking full names, " \
              "numbered in notice order: #{group.map { |i| names[i] }.join(' / ')}"
            )
          end
        end

        # The suffix replaces the tail rather than following it, because the
        # sanitizer cuts ids at MAX_ID_LENGTH and would drop it.
        def numbered_reference(base, number)
          suffix = "-#{number}"
          sanitize_id("#{sanitize_id(base)[0, Ammitto::Utils::IriSanitizer::MAX_ID_LENGTH - suffix.length]}#{suffix}")
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

        def create_entry(entity, announcement, entity_id, legal_citations, ref)
          list_info = LIST_TYPE_MAPPING[entity.list_type_code] || {
            code: entity.list_type_code.to_s.upcase,
            name: entity.sanction_list,
            authority: 'MOFCOM',
            list_slug: entity.list_type_code.to_s.gsub('_', '-')
          }

          Ammitto::SanctionEntry.new(
            id: generate_entry_id(ref, entry_list_type: list_info[:list_slug]),
            entity_id: entity_id,
            authority: authority,
            regime: create_regime(code: list_info[:code], name: list_info[:name]),
            effects: transform_effects(entity.measures),
            reasons: transform_reasons(entity.reason),
            period: create_temporal_period(entity),
            status: 'active',
            reference_number: ref,
            # transform_announcement already built and reported this block;
            # reporting it again per entry would count one bad cell many times.
            announcement: create_official_announcement(announcement.announcement, report_failures: false),
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
            effective_date: parse_date(entity.effective_date, source: :cn, field: :effective_date),
            effective_time: entity.effective_time,
            is_indefinite: true
          )
        end

        def create_official_announcement(announcement_block, report_failures: true)
          id = generate_announcement_id(naming_id(announcement_block&.document_id, :document_id))
          report_as = report_failures ? { source: :cn, field: :publish_date } : {}

          Ammitto::OfficialAnnouncement.new(
            id: id,
            title: extract_announcement_title(announcement_block),
            url: announcement_block.url,
            publish_date: parse_date(announcement_block.publish_date, **report_as),
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
            target_announcement_date: parse_date(modification.target_announcement_date,
                                                 source: :cn, field: :target_announcement_date),
            action: modification.action,
            effective_date: parse_date(modification.effective_date, source: :cn, field: :effective_date),
            effective_time: modification.effective_time,
            until_date: parse_date(modification.until_date, source: :cn, field: :until_date),
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
          target_ref = naming_id(target_id, :target_announcement_id)
          "https://www.ammitto.org/modification/cn/#{local_id}-#{target_ref}"
        end

        # An IRI is minted from this id, so one that is absent or sanitizes
        # to the shared fallback (blank, only punctuation, only Chinese
        # script, or "unknown" itself) would give every such file the same
        # IRI, each overwriting the others in the export.
        # @raise [Ammitto::ParseError] when the id cannot name anything
        def naming_id(raw_id, field)
          id = sanitize_id(raw_id)
          return id unless id == UNUSABLE_ID

          raise Ammitto::ParseError.new(
            "cn record has no usable #{field} (#{raw_id.inspect}), " \
            'so it cannot be told apart from any other lacking one',
            format: :yaml
          )
        end
      end
    end
  end
end

# Backward compatibility alias
Ammitto::Transformers::CnTransformer = Ammitto::Sources::Cn::Transformer
