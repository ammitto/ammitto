# frozen_string_literal: true

module Ammitto
  module Cmd
    module Harmonize
      # JP announcement handling, split out of SourceTransforms because it
      # alone (detection, per-record flattening, and positional id
      # derivation for data-jp's two announcement shapes) carries as much
      # weight as every other source's transform_<source> method combined.
      module JpAnnouncementTransform
        private

        # Whether a JP record is an announcement file rather than a flat
        # per-entity record. `fetch jp` writes no per-entity YAML (the
        # source is a PDF), so every file discovery reaches is an
        # announcement under data-jp/sources/sanction-lists. data-jp ships
        # two shapes: entities at the top level, and entities nested under
        # sanction_details.
        # @param data [Hash] source data
        # @return [Boolean]
        def jp_announcement?(data)
          data.is_a?(Hash) && data.key?('announcement') &&
            !jp_announcement_entities(data).empty?
        end

        # The entity records an announcement file carries, from whichever
        # of the two shapes it uses
        # @param data [Hash] source data
        # @return [Array<Hash>] entity records
        def jp_announcement_entities(data)
          top = data['entities']
          return top if top.is_a?(Array)

          details = data['sanction_details']
          nested = details.is_a?(Hash) ? details['entities'] : nil
          nested.is_a?(Array) ? nested : []
        end

        # Transform a JP announcement file into one result per entity.
        # Each record is flattened to the per-entity shape Jp::Entity
        # already reads, so the announcement layout and the flat layout
        # share one transform path (as transform_cn_announcement does
        # for CN).
        # @param transformer [Object] transformer instance
        # @param data [Hash] source data
        # @return [Array<Hash>] one entity/entry pair per record
        def transform_jp_announcement(transformer, data)
          announcement = data['announcement']
          announcement = {} unless announcement.is_a?(Hash)

          jp_announcement_entities(data).each_with_index.map do |rec, index|
            source = Ammitto::Sources::Jp::Entity.from_hash(
              jp_flatten_record(rec, announcement, index + 1)
            )
            result = transformer.transform(source)

            {
              entity: entity_to_hash(result[:entity]),
              entry: entry_to_hash(result[:entry])
            }
          end
        end

        # Flatten one announcement entity record to the keys
        # Jp::Entity.from_hash reads
        # @param record [Hash] announcement entity record
        # @param announcement [Hash] the file's announcement header
        # @param position [Integer] 1-based position within the file
        # @return [Hash] flat per-entity hash
        def jp_flatten_record(record, announcement, position)
          name = record['name']
          name = {} unless name.is_a?(Hash)

          {
            'id' => jp_record_id(record, announcement, position),
            'name' => name['en'] || name['ja'],
            'name_ja' => name['ja'],
            'entity_type' => record['type'],
            'addresses' => Array(record['address'])
                           .reject { |a| a.to_s.strip.empty? },
            'source_url' => announcement['source_url'] || announcement['url'],
            'remarks' => jp_record_remarks(record)
          }.compact
        end

        # Local id for one announcement record. A published id wins; only a
        # record carrying none gets one derived from the announcement's
        # authority, the list it belongs to, and its position in the file.
        #
        # The derivation exists because data-jp's fefta-list/20250131.yml
        # holds a whole list published without a single `id`, and the IRI
        # layer refuses (correctly) to mint "unknown" for them — leaving
        # the whole source unharmonizable. The shape mirrors the ids
        # data-jp hand-authors (jp.mof.milosevic.1), and position — not
        # name — is the disambiguator: IriSanitizer strips non-ASCII, so
        # some names sanitize to the same empty string and a name-derived id
        # would silently merge them. Position is also what
        # keeps a JP IRI stable across republications:
        # mof-asset-freeze/01-milosevic's 20260305.yml and 20260306.yml
        # reuse jp.mof.milosevic.1..10 verbatim.
        #
        # entry_number is used as the trailing number rather than as the id
        # outright: it is unique only within a list, so publishing it alone
        # would collide across lists. Blank segments are dropped instead of
        # aborting, because returning nil here raises MissingLocalIdError
        # and takes the whole source down — the very failure this method
        # exists to prevent.
        # @param record [Hash] announcement entity record
        # @param announcement [Hash] the file's announcement header
        # @param position [Integer] 1-based position within the file
        # @return [String] local id
        def jp_record_id(record, announcement, position)
          id = record['id']
          return id if id.is_a?(String) && !id.strip.empty?

          authority = jp_id_segment(announcement['authority'])
          list = jp_id_segment(record['sanction_list'] ||
                               record['sanction_list_en'] ||
                               announcement['type'])
          number = record['entry_number'] || position

          ['jp', authority, list, number]
            .reject { |segment| segment.to_s.strip.empty? }.join('.')
        end

        # The trailing token of a slash-separated JP identifier
        # ('jp/meti' -> 'meti'), which is the segment the hand-authored ids
        # are built from.
        # @param value [Object] identifier such as 'jp/meti'
        # @return [String] trailing token, empty when unusable
        def jp_id_segment(value)
          value.to_s.strip.split('/').last.to_s.strip
        end

        # Join an announcement record's free-text notes into one string.
        # The two shapes name the field differently (remarks / reason), and
        # many records carry both, so both are read: preferring one would drop
        # text those records published.
        # @param record [Hash] announcement entity record
        # @return [String, nil] joined text
        def jp_record_remarks(record)
          texts = [record['remarks'], record['reason']]
                  .flat_map { |notes| jp_note_texts(notes) }

          texts.empty? ? nil : texts.join(' ')
        end

        # Texts of one notes field: a plain string, or a list of
        # per-language hashes where English is preferred and Japanese
        # used when an item has no English text
        # @param notes [Object] the notes field
        # @return [Array<String>] extracted texts
        def jp_note_texts(notes)
          return [notes] if notes.is_a?(String)
          return [] unless notes.is_a?(Array)

          notes.filter_map do |note|
            next note if note.is_a?(String)
            next nil unless note.is_a?(Hash)

            note['en'] || note['ja']
          end
        end
      end
    end
  end
end
