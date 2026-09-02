# frozen_string_literal: true

require 'digest'
require 'json'
require_relative '../../transformers/base_transformer'
require_relative '../../utils/iri_sanitizer'
require_relative '../../ontology/types'
require_relative '../../official_announcement'
require_relative '../../person_entity'
require_relative '../../organization_entity'
require_relative '../../sanction_entry'
require_relative '../../sanction_reason'
require_relative '../../temporal_period'
require_relative '../../ontology/sanction/sanction_group'
require_relative '../../ontology/value_objects/localized_string'

module Ammitto
  module Sources
    module Ru
      # Turns one MID announcement into harmonized models.
      #
      # data-ru stores a document per announcement with the parties named
      # inside it, which is the shape data-cn uses and publishes from.
      # `Sources::Ru::Transformer` reads one flat record at a time and
      # cannot see inside a document; this reads the document.
      #
      # The return contract matches Sources::Cn::Transformer's, so
      # harmonize treats the two sources alike.
      #
      class AnnouncementTransformer < Ammitto::Transformers::BaseTransformer
        # Regimes for the lists MID publishes, by list code.
        #
        # Defined here rather than taken from Transformer's copy: that
        # would make the two files require each other, and this class is
        # loaded first.
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

        # Transform an announcement and everyone it names.
        #
        # @param announcement [Ammitto::Sources::Ru::Announcement]
        # @return [Hash] entities, entries, group, official_announcement and
        #   legal_citations, the same contract Sources::Cn::Transformer
        #   returns so harmonize can treat the two sources alike
        def transform_announcement(announcement)
          citations = announcement_legal_citations(announcement.instruments)
          official = official_announcement_from(announcement.announcement)

          results = announcement.entities
                                .zip(announcement_references(announcement))
                                .map do |entity, reference|
            transform_announcement_entity(entity, reference, citations,
                                          announcement)
          end
          entities = results.map { |result| result[:entity] }
          entries = results.map { |result| result[:entry] }

          group = announcement_group(announcement, official, entities, entries)
          entries.each { |entry| entry.group_id = group.id } if group

          {
            entities: entities,
            entries: entries,
            group: group,
            official_announcement: official,
            legal_citations: citations
          }
        end

        private

        def transform_announcement_entity(entity, reference, citations,
                                          announcement)
          if entity.person?
            transform_announcement_person(entity, reference, citations,
                                          announcement)
          else
            transform_announcement_organization(entity, reference, citations,
                                                announcement)
          end
        end

        def transform_announcement_person(entity, reference, citations,
                                          announcement)
          entity_id = generate_entity_id(reference)
          entry = create_announcement_entry(entity, reference, entity_id,
                                            citations, announcement)

          # MID states nationality and never gender, so the field CN fills
          # with gender stays empty here rather than being guessed at.
          person = Ammitto::PersonEntity.new(
            id: entity_id,
            entity_type: 'person',
            names: announcement_names(entity),
            nationalities: [entity.nationality].compact,
            remarks: announcement_entity_remarks(entity)
          )
          person.add_sanction_entry(entry)

          { entity: person, entry: entry }
        end

        def transform_announcement_organization(entity, reference, citations,
                                                announcement)
          entity_id = generate_entity_id(reference)
          entry = create_announcement_entry(entity, reference, entity_id,
                                            citations, announcement)

          organization = Ammitto::OrganizationEntity.new(
            id: entity_id,
            entity_type: 'organization',
            names: announcement_names(entity),
            remarks: announcement_entity_remarks(entity)
          )
          organization.add_sanction_entry(entry)

          { entity: organization, entry: entry }
        end

        # A reference for every party the announcement names, in order.
        #
        # MID gives a party no identifier of its own, so identity comes
        # from where it was named plus the name. Two things break that on
        # the real corpus, and both lose records rather than announcing
        # themselves: `sanitize_id` drops Cyrillic, so a party named only
        # in Cyrillic sanitizes to the shared literal "unknown" — seven
        # distinct people in one announcement collapsed onto one node —
        # and the name is cut at 31 characters first, so two long names
        # can meet.
        #
        # Where the readable part cannot stand alone, a digest of the
        # party's own record settles it. Taken from content, so it is the
        # same on every run and survives the upstream reordering that a
        # positional suffix would not.
        #
        # @param announcement [Ammitto::Sources::Ru::Announcement]
        # @return [Array<String>] one reference per entity, in order
        def announcement_references(announcement)
          document_id = sanitize_id(announcement.document_id || 'RU')
          slugs = announcement.entities.map { |e| entity_name_slug(e) }
          counts = slugs.tally

          announcement.entities.zip(slugs).map do |entity, slug|
            local = if slug == Utils::IriSanitizer::DEFAULT_ID ||
                       counts[slug] > 1
                      "#{slug}-#{record_digest(entity)}"
                    else
                      slug
                    end
            "#{document_id}-#{local}"
          end
        end

        def entity_name_slug(entity)
          name = entity.english_name || entity.russian_name
          sanitize_id(name.to_s[0..30])
        end

        # @param entity [Ammitto::Sources::Ru::Entity]
        # @return [String] eight hex characters of the record's digest
        def record_digest(entity)
          Digest::SHA256.hexdigest(
            JSON.generate(canonical_record(entity.to_hash))
          )[0, 8]
        end

        # Key-sorted JSON, not YAML.
        #
        # These digests end up inside published IRIs, so the same record
        # has to give the same digest on every machine that harmonizes
        # it. YAML formatting is Psych's business and can change between
        # Ruby versions, which would rename every disambiguated entity
        # the day the runner's interpreter moved. Array order is left
        # alone: it is the source's own ordering of reasons and measures.
        #
        # @param value [Object] a value from the record
        # @return [Object] the same value, deterministically ordered
        def canonical_record(value)
          case value
          when Hash
            value.sort_by { |key, _| key.to_s }
                 .to_h { |key, inner| [key.to_s, canonical_record(inner)] }
          when Array
            value.map { |inner| canonical_record(inner) }
          else
            value
          end
        end

        # The field a name arrives in says which language RU meant it to
        # be; it does not say what script the text is written in, and the
        # two disagree in the corpus. Seven parties in
        # sources/announcements/20250926.yml carry an empty `ru` and a
        # Cyrillic name under `en` -- "Бирн, Джеймс", "Дуган, Дэвид
        # Майкл" and five more. Taking the script from the field stamped
        # those as Latn, so a consumer transliterating or collating by
        # script was told Cyrillic text was Latin.
        #
        # The script is read from the text instead. The field still
        # decides which name leads: `en` is RU's own romanisation and is
        # the primary when present, whatever script it turns out to hold.
        def announcement_names(entity)
          english = entity.english_name.to_s.strip
          russian = entity.russian_name.to_s.strip
          names = []

          unless english.empty?
            names << create_name_variant(full_name: english,
                                         script: script_for(english),
                                         is_primary: true)
          end
          unless russian.empty?
            names << create_name_variant(full_name: russian,
                                         script: script_for(russian),
                                         is_primary: english.empty?)
          end

          names
        end

        # @return [String] the ISO 15924 code for the text's own script
        def script_for(text) = Ammitto::Ontology::Types.detect_script(text).to_s

        def create_announcement_entry(entity, reference, entity_id,
                                      citations, announcement)
          list_info = announcement_list_info(entity)

          Ammitto::SanctionEntry.new(
            id: generate_entry_id(reference,
                                  entry_list_type: list_info[:list_slug]),
            entity_id: entity_id,
            authority: authority,
            regime: create_regime(code: list_info[:code],
                                  name: list_info[:name]),
            effects: announcement_effects(entity.measures),
            reasons: announcement_reasons(entity.reason),
            period: announcement_period(entity),
            status: 'active',
            reference_number: reference,
            announcement: official_announcement_from(announcement.announcement),
            legal_citations: citations,
            raw_source_data: announcement_raw_source_data(entity)
          )
        end

        # The regime and slug for the list a party is on.
        #
        # The slug is derived from the code rather than fixed, so a party
        # on a list other than the stop-list does not silently take the
        # stop-list's entry IRI.
        def announcement_list_info(entity)
          code = entity.list_type_code.to_s
          slug = code.tr('_', '-')
          mapped = LIST_TYPE_MAPPING[code]
          return mapped.merge(list_slug: slug) if mapped

          { code: "RU_#{code.upcase}", name: entity.sanction_list,
            list_slug: slug }
        end

        def announcement_raw_source_data(entity)
          create_raw_source_data(
            source_format: 'yaml',
            source_specific_fields: {
              'ru:list_type' => entity.list_type_code,
              'ru:sanction_list' => entity.sanction_list,
              'ru:russian_name' => entity.russian_name,
              'ru:english_name' => entity.english_name,
              'ru:nationality' => entity.nationality
            }
          )
        end

        def announcement_reasons(reasons)
          return [] if reasons.nil? || reasons.empty?

          reasons.filter_map do |reason|
            descriptions = localized_announcement_strings(reason)
            next if descriptions.empty?

            Ammitto::SanctionReason.new(category: 'other',
                                        description: descriptions)
          end
        end

        # @param values [Hash, nil] one text keyed by language
        # @return [Array<LocalizedString>] the non-blank ones
        def localized_announcement_strings(values)
          return [] unless values.is_a?(Hash)

          [
            localized_announcement_string(values['ru'], language: 'ru',
                                                        script: 'Cyrl',
                                                        primary: true),
            localized_announcement_string(values['en'], language: 'en',
                                                        script: 'Latn',
                                                        primary: false)
          ].compact
        end

        def localized_announcement_string(value, language:, script:, primary:)
          text = value.to_s.strip
          return nil if text.empty?

          Ammitto::Ontology::ValueObjects::LocalizedString.new(
            value: text, language: language, script: script,
            is_primary: primary
          )
        end

        # Every type a measure carries becomes an effect.
        #
        # CN keeps only the first; the schema allows several and dropping
        # the rest would publish a narrower sanction than was imposed.
        # RU announcements do not always say what a measure does, and this
        # method used to answer that silence with 'entry_ban' twice over:
        # once for a party carrying no measures at all, once for a measure
        # whose type list was empty. Both invent a sanction the source
        # never stated, against a named person, on a register other people
        # act on. A reader cannot tell an invented entry ban from a real
        # one.
        #
        # Absence is published as absence. No measures yields no effects.
        # A measure that carries a description but no type yields one
        # effect holding that description and no type, so the source's
        # own words survive without a category being put in its mouth --
        # SanctionEntry#effect_types compacts nils, so a typeless effect
        # is a shape the model already expects. A measure carrying neither
        # a type nor a description says nothing and produces nothing.
        def announcement_effects(measures)
          return [] if measures.nil? || measures.empty?

          measures.flat_map do |measure|
            descriptions = announcement_measure_descriptions(measure)
            types = measure.type
            types = [nil] if types.nil? || types.empty?

            types.filter_map do |type|
              # Neither a type nor a word: the measure says nothing, so
              # there is nothing to publish about it.
              next if type.nil? && descriptions.empty?

              create_effect(effect_type: type, scope: 'full',
                            description: descriptions)
            end
          end
        end

        def announcement_measure_descriptions(measure)
          localized_announcement_strings(
            'ru' => measure.russian_description,
            'en' => measure.english_description
          )
        end

        # RU records no time of day against a party, only a date. Reading
        # the announcement's publication time into the period would turn
        # document metadata into a claim about when a sanction bit.
        def announcement_period(entity)
          Ammitto::TemporalPeriod.new(
            effective_date: parse_date(entity.effective_date),
            is_indefinite: entity.effective_date.nil?
          )
        end

        def official_announcement_from(block)
          return nil unless block

          Ammitto::OfficialAnnouncement.new(
            id: generate_announcement_id(
              sanitize_id(block.document_id || 'unknown')
            ),
            title: announcement_title(block),
            url: block.url,
            publish_date: parse_date(block.publish_date),
            publish_time: block.publish_time,
            document_id: block.document_id,
            document_type: block.type,
            signatory: block.signatory,
            publisher: block.publisher,
            authority: block.authority,
            content: announcement_content(block),
            language: announcement_language(block)
          )
        end

        # data-ru keeps both translations in one hash where data-cn keeps a
        # list of single-language maps, so the accessors differ.
        def announcement_title(block)
          block.title&.dig('ru') || block.title&.dig('en')
        end

        # OfficialAnnouncement holds one string. The document declares its
        # own language, so that translation is the one to keep.
        def announcement_content(block)
          block.content&.dig(announcement_language(block)) ||
            block.content&.dig('ru') ||
            block.content&.dig('en')
        end

        def announcement_language(block)
          language = block.lang.to_s.strip
          language.empty? ? 'ru' : language
        end

        def announcement_entity_remarks(entity)
          title = announcement_entity_title(entity)
          parts = []
          parts << "List: #{entity.sanction_list}" if entity.sanction_list
          parts << "Title: #{title}" if title
          parts << "Nationality: #{entity.nationality}" if entity.nationality
          parts.join('; ')
        end

        def announcement_entity_title(entity)
          entity.title&.dig('ru') || entity.title&.dig('en')
        end

        def announcement_legal_citations(instruments)
          return [] if instruments.nil? || instruments.empty?

          instruments.map do |instrument|
            local_id = instrument.id&.sub(%r{^ru/}, '')
            local_id ||= sanitize_id(instrument.law || 'unknown')
            instrument.to_legal_citation(
              instrument_id: generate_legal_instrument_id(local_id)
            )
          end
        end

        # One announcement naming several parties is a group.
        def announcement_group(announcement, official, entities, entries)
          return nil unless entities.size > 1

          Ammitto::Ontology::Sanction::SanctionGroup.new(
            id: announcement_group_id(official&.id),
            announcement_id: official&.id,
            announcement_title: announcement_title(announcement.announcement),
            entry_ids: entries.map(&:id),
            entity_count: entities.size,
            effective_date: parse_date(
              announcement.entities.first&.effective_date
            ),
            notes: "Group of #{entities.size} entities sanctioned together"
          )
        end

        def announcement_group_id(announcement_id)
          local_id = announcement_id.to_s.split('/').last
          "https://www.ammitto.org/group/ru/#{local_id}"
        end
      end
    end
  end
end
