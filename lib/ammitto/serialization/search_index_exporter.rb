# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'
require_relative '../utils/presence'

module Ammitto
  module Serialization
    # SearchIndexExporter creates a lightweight search index for client-side search
    #
    # The website currently loads 69MB of JSON-LD data. This exporter creates
    # a lightweight (~5-10MB) search-index.json with only essential fields,
    # allowing full entity data to be loaded on-demand from node files.
    #
    # Rows are deduplicated by entity @id: one search row per entity,
    # however many entity/entry pairs the input carries. Repeated ids
    # aggregate into the existing row — names are unioned, missing or
    # blank fields are filled, and present scalar fields keep their
    # first-seen value. The type/status defaults (person/active) apply
    # after aggregation, so a later pair carrying the real value can
    # still fill it. Facets are recomputed from the deduplicated rows,
    # so facet counts, search rows, and the deduplicated stats.json
    # numbers agree.
    #
    # @example Using the search index exporter
    #   exporter = SearchIndexExporter.new
    #
    #   # Add entities during harmonization
    #   exporter.add(entity_hash, entry_hash)
    #
    #   # Export search index and facets
    #   exporter.export('./api/v1')
    #
    class SearchIndexExporter
      # Bounds of a stated span of birth years, in both spellings the
      # exporter has to read.
      BIRTH_YEAR_FROM_KEYS = %w[yearRangeFrom year_range_from].freeze
      BIRTH_YEAR_TO_KEYS = %w[yearRangeTo year_range_to].freeze

      # birthYears/birthYearKind/birthCirca (#merge_row) describe one set
      # of years and must move as a unit. birthCirca is absent whenever it
      # is false (#birth_year_fields), so a generic per-key fill would
      # treat an existing row's true-less pair as still having a gap and
      # fill birthCirca in from a LATER pair's different years — flagging
      # the first-seen years circa on the strength of a hedge that was
      # never about them.
      BIRTH_YEAR_ROW_KEYS = %i[birthYears birthYearKind birthCirca].freeze

      # A published year, wherever it comes from, is exactly four digits.
      FOUR_DIGIT_YEAR = /\A\d{4}\z/

      # Authority names for facet display
      AUTHORITY_NAMES = {
        'un' => 'United Nations',
        'eu' => 'European Union',
        'uk' => 'United Kingdom',
        'us' => 'United States',
        'au' => 'Australia',
        'ca' => 'Canada',
        'ch' => 'Switzerland',
        'cn' => 'China',
        'ru' => 'Russia',
        'tr' => 'Turkey',
        'nz' => 'New Zealand',
        'jp' => 'Japan',
        'wb' => 'World Bank',
        'eu_vessels' => 'EU Vessels',
        'un_vessels' => 'UN Vessels'
      }.freeze

      # Entity type display info
      ENTITY_TYPES = {
        'person' => { name: 'Person', icon: 'user' },
        'organization' => { name: 'Organization', icon: 'building' },
        'vessel' => { name: 'Vessel', icon: 'ship' },
        'aircraft' => { name: 'Aircraft', icon: 'plane' }
      }.freeze

      # Initialize the search index exporter
      def initialize
        @rows_by_id = {}
        @regime_names = {}
      end

      # Deduplicated search rows (one per entity @id), with post-merge
      # defaults applied
      # @return [Array<Hash>] entities for search index
      def entities
        @rows_by_id.values.map { |row| finalize_row(row) }
      end

      # Facet counts recomputed from the deduplicated rows
      # @return [Hash] facet counts
      def facets
        build_facets
      end

      # Add entity to search index, aggregating repeated entity ids
      # @param entity [Hash] full entity data
      # @param entry [Hash] sanction entry data
      # @return [void]
      def add(entity, entry)
        # Support both '@id' (JSON-LD) and 'id' (model hash) formats.
        # The id is the dedup key, so it takes the same String rule as
        # the row scalars: a blank '@id' is truthy in Ruby, and would
        # both mask a usable 'id' and collapse every blank-id entity
        # into one shared row
        entity_id = string_presence(entity['@id']) ||
                    string_presence(entity['id'])
        return unless entity_id

        regime_code = string_presence(extract_regime_code(entry))
        remember_regime_name(regime_code, entry)

        search_entity = build_row(entity_id, entity, entry, regime_code)

        existing = @rows_by_id[entity_id]
        if existing
          merge_row(existing, search_entity)
        else
          @rows_by_id[entity_id] = search_entity
        end
      end

      # Export search index and facets to output directory
      # @param output_dir [String] output directory path
      # @return [void]
      def export(output_dir)
        export_search_index(output_dir)
        export_facets(output_dir)
      end

      private

      # Build one lightweight search row
      # @param entity_id [String] entity id
      # @param entity [Hash] full entity data
      # @param entry [Hash] sanction entry data
      # @param regime_code [String, nil] regime code
      # @return [Hash] search row
      def build_row(entity_id, entity, entry, regime_code)
        {
          id: entity_id,
          ref: extract_ref(entity_id),
          # Support both camelCase and snake_case entity type; defaults
          # apply post-merge (#finalize_row), not here, so a later
          # duplicate pair carrying the real value can still fill it
          type: string_presence(entity['entityType'] || entity['entity_type']),
          names: string_list(extract_names(entity)),
          primaryName: string_presence(extract_primary_name(entity)),
          country: string_presence(extract_country(entity)),
          regime: regime_code,
          authority: string_presence(extract_authority_code(entry)),
          listType: string_presence(extract_list_type(entry)),
          status: string_presence(entry['status']),
          **birth_year_fields(entity),
          imo: scalar_presence(extract_imo(entity))
        }.compact
      end

      # The three-field shape (#extract_birth_year_info) collapsed into
      # the keys #build_row spreads into the row. Kept as its own method
      # so the empty case ({}) reads as "contribute nothing" rather than
      # three explicit nils threaded through the caller.
      # @param entity [Hash] entity data
      # @return [Hash] birthYears/birthYearKind/birthCirca, or empty
      def birth_year_fields(entity)
        info = extract_birth_year_info(entity)
        return {} unless info

        {
          birthYears: info[:years],
          birthYearKind: info[:kind],
          birthCirca: info[:circa] || nil
        }
      end

      # Only non-blank Strings become row scalars: blanks must not block
      # a later real value, and wrong-typed source values (numbers,
      # hashes) must never reach the facet builders' String calls
      # @param value [Object] candidate value
      # @return [String, nil]
      def string_presence(value)
        return nil unless value.is_a?(String)

        Utils::Presence.present?(value) ? value : nil
      end

      # Names obey the same String rule as the row scalars: the
      # extractors guard on truthiness, so blanks and wrong-typed source
      # values (numbers, hashes) would otherwise reach search-index.json
      # @param values [Array<Object>] candidate names
      # @return [Array<String>] non-blank String names
      def string_list(values)
        Array(values).filter_map { |value| string_presence(value) }
      end

      # IMO numbers legitimately arrive numeric in some sources; coerce
      # Numerics, otherwise apply the String rule
      # @param value [Object] candidate value
      # @return [String, nil]
      def scalar_presence(value)
        return value.to_s if value.is_a?(Numeric)

        string_presence(value)
      end

      # Post-aggregation defaults for the exported row shape
      # @param row [Hash] stored search row
      # @return [Hash] finalized copy
      def finalize_row(row)
        finalized = row.dup
        finalized[:type] ||= 'person'
        finalized[:status] ||= 'active'
        finalized
      end

      # Aggregate a repeated entity id into its existing row: union the
      # names, fill fields the row lacks, keep first-seen values otherwise
      # @param existing [Hash] stored search row
      # @param incoming [Hash] newly built row for the same entity id
      # @return [void]
      def merge_row(existing, incoming)
        merged_names = (existing[:names] || []) | (incoming[:names] || [])
        existing[:names] = merged_names unless merged_names.empty?

        birth_years_settled = BIRTH_YEAR_ROW_KEYS.any? { |key| existing.key?(key) }

        incoming.each do |key, value|
          next if BIRTH_YEAR_ROW_KEYS.include?(key) && birth_years_settled

          existing[key] = value unless existing.key?(key)
        end
      end

      # Record a regime display name for facet output (String-typed, so
      # a wrong-typed source name can never leak into facets)
      # @param regime_code [String, nil] regime code
      # @param entry [Hash] entry data
      # @return [void]
      def remember_regime_name(regime_code, entry)
        return unless regime_code

        name = entry['regime']['name'] if entry['regime'].is_a?(Hash)
        @regime_names[regime_code] ||= string_presence(name)
      end

      # Recompute facet counts from the deduplicated, finalized rows
      # @return [Hash] facet counts
      def build_facets
        facets = empty_facets

        entities.each do |row|
          facets[:authorities][row[:authority]] += 1 if row[:authority]
          facets[:list_types][row[:listType]] += 1 if row[:listType]
          count_regime_facet(facets, row[:regime])
          facets[:types][row[:type]] += 1 if row[:type]
          facets[:countries][row[:country].upcase] += 1 if row[:country]
          facets[:statuses][row[:status]] += 1 if row[:status]
        end

        facets
      end

      # @return [Hash] empty facet structure
      def empty_facets
        {
          authorities: Hash.new(0),
          list_types: Hash.new(0),
          regimes: {},
          types: Hash.new(0),
          countries: Hash.new(0),
          statuses: Hash.new(0)
        }
      end

      # Count one row's regime into the facets
      # @param facets [Hash] facet accumulator
      # @param regime_code [String, nil] regime code
      # @return [void]
      def count_regime_facet(facets, regime_code)
        return unless regime_code

        regime = facets[:regimes][regime_code] ||=
          { count: 0, name: @regime_names[regime_code] }
        regime[:count] += 1
      end

      # Extract reference path from entity ID
      # @param entity_id [String] full entity ID or simple ID
      # @return [String] short reference (e.g., "un/KPi.066" or "au/1234")
      def extract_ref(entity_id)
        # Try to extract from full URI format "https://www.ammitto.org/entity/un/KPi.066"
        match = entity_id.match(%r{/entity/([^/]+/[^/]+)$})
        return match[1] if match

        # If it's already in "source/ref" format, return as-is
        return entity_id if entity_id.include?('/')

        # Otherwise return the ID as-is
        entity_id
      end

      # Extract authority code from entry
      # @param entry [Hash] entry data
      # @return [String, nil] authority code
      def extract_authority_code(entry)
        return nil unless entry

        authority = entry['authority']

        # Direct string value
        return authority.downcase if authority.is_a?(String)

        # Check for @id reference. All three lookups take the String rule:
        # the extractor calls #match/#downcase, so a wrong-typed source
        # value would raise NoMethodError mid-harmonize instead of
        # dropping out of the row
        if authority.is_a?(Hash)
          id = string_presence(authority['@id'])
          if id
            # Extract from "https://www.ammitto.org/authority/un"
            match = id.match(%r{/authority/([^/]+)$})
            return match[1] if match
          end

          # JsonLdSerializer emits 'id', never '@id'. Under harmonize the
          # graph exporter rewrites that hash into the '@id' reference
          # above first, but this exporter is documented for standalone
          # use too, and there the authority's own id is the answer.
          # countryCode is the last resort because distinct authorities
          # share a country
          own_id = string_presence(authority['id'])
          return own_id.downcase if own_id

          return string_presence(authority['countryCode'])&.downcase
        end

        nil
      end

      # Extract regime code from entry
      # @param entry [Hash] entry data
      # @return [String, nil] regime code
      def extract_regime_code(entry)
        return nil unless entry

        # Check for @id reference (same String rule as the authority
        # extractor: #match and #downcase must never see a non-String)
        if entry['regime'].is_a?(Hash)
          id = string_presence(entry['regime']['@id'])
          if id
            # Extract from "https://www.ammitto.org/regime/dprk"
            match = id.match(%r{/regime/([^/]+)$})
            return match[1] if match
          end
          return string_presence(entry['regime']['code'])&.downcase
        end

        nil
      end

      # Extract list type from entry
      # @param entry [Hash] entry data
      # @return [String, nil] list type
      def extract_list_type(entry)
        return nil unless entry

        # Check for list_type field (normalized structure). A blank or
        # wrong-typed field must not mask the IRI fallback below, which
        # may still carry the real list identity
        list_type = string_presence(entry['list_type']) ||
                    string_presence(entry['listType'])
        return list_type if list_type

        # Try to extract from entry @id (String rule: #match below)
        entry_id = string_presence(entry['@id']) ||
                   string_presence(entry['id'])
        return nil unless entry_id

        # Pattern: BASE_URI/entry/{source}/{list_type}/{local_id}
        match = entry_id.match(%r{/entry/[^/]+/([^/]+)})
        match ? match[1] : nil
      end

      # Extract all names from entity
      # @param entity [Hash] entity data
      # @return [Array<String>] list of names
      def extract_names(entity)
        names = []

        # From names array
        if entity['names'].is_a?(Array)
          entity['names'].each do |name|
            if name.is_a?(Hash)
              # Support both camelCase and snake_case keys
              names << name['fullName'] if name['fullName']
              names << name['full_name'] if name['full_name']
              names << name['lastName'] if name['lastName']
              names << name['last_name'] if name['last_name']
              names << name['firstName'] if name['firstName']
              names << name['first_name'] if name['first_name']
              names << name['middleName'] if name['middleName']
              names << name['middle_name'] if name['middle_name']
            elsif name.is_a?(String)
              names << name
            end
          end
        end

        # From name field
        names << entity['name'] if entity['name']

        # From aliases
        if entity['aliases'].is_a?(Array)
          entity['aliases'].each do |alias_obj|
            if alias_obj.is_a?(Hash)
              names << alias_obj['name'] if alias_obj['name']
              names << alias_obj['full_name'] if alias_obj['full_name']
              names << alias_obj['fullName'] if alias_obj['fullName']
            elsif alias_obj.is_a?(String)
              names << alias_obj
            end
          end
        end

        names.uniq.compact
      end

      # Extract primary name from entity
      # @param entity [Hash] entity data
      # @return [String, nil] primary name
      def extract_primary_name(entity)
        # From names array - find primary
        if entity['names'].is_a?(Array)
          primary = entity['names'].find do |name|
            name.is_a?(Hash) && (name['isPrimary'] == true || name['is_primary'] == true)
          end
          # Support both camelCase and snake_case
          return primary['fullName'] if primary&.dig('fullName')
          return primary['full_name'] if primary&.dig('full_name')
        end

        # Fall back to first name
        if entity['names'].is_a?(Array) && entity['names'].first.is_a?(Hash)
          first = entity['names'].first
          return first['fullName'] if first['fullName']
          return first['full_name'] if first['full_name']
        end

        # Fall back to name field
        entity['name']
      end

      # Extract country from entity
      # @param entity [Hash] entity data
      # @return [String, nil] country code
      def extract_country(entity)
        # From nationality
        if entity['nationalities'].is_a?(Array) && entity['nationalities'].first
          nat = entity['nationalities'].first
          return nat['countryCode'] if nat.is_a?(Hash) && nat['countryCode']
          return nat['country_code'] if nat.is_a?(Hash) && nat['country_code']
          return nat if nat.is_a?(String)
        end

        # From citizenship
        if entity['citizenships'].is_a?(Array) && entity['citizenships'].first
          cit = entity['citizenships'].first
          return cit['countryCode'] if cit.is_a?(Hash) && cit['countryCode']
          return cit['country_code'] if cit.is_a?(Hash) && cit['country_code']
        end

        # From addresses
        if entity['addresses'].is_a?(Array) && entity['addresses'].first
          addr = entity['addresses'].first
          return addr['countryCode'] if addr.is_a?(Hash) && addr['countryCode']
          return addr['country_code'] if addr.is_a?(Hash) && addr['country_code']
          return addr['country'] if addr.is_a?(Hash) && addr['country']
        end

        # From birth info
        if entity['birthInfo'].is_a?(Array) && entity['birthInfo'].first
          birth = entity['birthInfo'].first
          return birth['countryCode'] if birth.is_a?(Hash) && birth['countryCode']
          return birth['country_code'] if birth.is_a?(Hash) && birth['country_code']
          return birth['country'] if birth.is_a?(Hash) && birth['country']
        end

        # Also check birth_info (snake_case)
        if entity['birth_info'].is_a?(Array) && entity['birth_info'].first
          birth = entity['birth_info'].first
          return birth['countryCode'] if birth.is_a?(Hash) && birth['countryCode']
          return birth['country_code'] if birth.is_a?(Hash) && birth['country_code']
          return birth['country'] if birth.is_a?(Hash) && birth['country']
        end

        nil
      end

      # The one place the row's birth-year shape is decided. Replaces the
      # four columns this exporter used to carry (birthYear, birthYearFrom,
      # birthYearTo, and a rejected fourth for multi-candidate entities)
      # with three that cover every scenario a source can state, so a new
      # scenario is a new `kind` value rather than a new column — see the
      # maintainer's ruling recorded in the PR this shipped in.
      #
      # Precedence, checked in this order:
      #   1. a stated span (#birth_info_with_range) — unless both bounds
      #      land on the same year, in which case the span collapses to
      #      an exact year rather than publishing a duplicate one-year
      #      "span"; a stated span never coexists with an exact year the
      #      way the old five-field shape let it.
      #   2. distinct years across every record naming one — more than one
      #      distinct year makes it "candidates" (no single one is
      #      entitled to stand alone as fact), exactly one makes it
      #      "exact".
      #   3. the legacy top-level birthDate/birth_date fields, for an
      #      entity with no birthInfo records at all.
      # @param entity [Hash] entity data
      # @return [Hash, nil] :kind, :years, :circa — or nil for no birth data
      def extract_birth_year_info(entity)
        entity_type = entity['entityType'] || entity['entity_type']
        return nil unless entity_type == 'person'

        span_info = extract_birth_year_span(entity)
        return span_info if span_info

        extract_birth_year_candidates(entity) || extract_birth_year_fallback(entity)
      end

      # @param entity [Hash] entity data
      # @return [Hash, nil] a span or same-year-collapsed exact result —
      #   nil when the record #birth_info_with_range found carries the
      #   range KEYS but neither value validates as a year, so the
      #   caller falls through to #extract_birth_year_candidates instead
      #   of publishing a malformed bound and losing a real year with it
      def extract_birth_year_span(entity)
        record = birth_info_with_range(entity)
        return nil unless record

        from = valid_year_bound(BIRTH_YEAR_FROM_KEYS.filter_map { |key| record[key] }.first)
        to = valid_year_bound(BIRTH_YEAR_TO_KEYS.filter_map { |key| record[key] }.first)
        return nil unless from || to

        circa = record['circa'] == true

        return { kind: 'exact', years: [from], circa: circa } if from && to && from == to

        # NOT .compact: position carries the bound's direction. An open
        # span keeps its missing end as `nil` rather than shifting the one
        # present bound down to index 0, which would make "1980 or later"
        # and "1980 or earlier" the same array.
        { kind: 'span', years: [from, to], circa: circa }
      end

      # Every birth record naming a date or year, not only the first or
      # the span-bearing one: an entity can carry several, one per
      # contributing source, and each one that names a year is a
      # candidate whether or not the others agree with it.
      #
      # Each record is resolved to its validated year ONCE and paired
      # with its own circa flag, so a record that failed to yield a year
      # (malformed date, blank, wrong type) cannot still contribute its
      # circa flag to years it had no part in publishing.
      # @param entity [Hash] entity data
      # @return [Hash, nil] "exact" (one distinct year) or "candidates"
      #   (more than one) — nil when no record names a valid year
      def extract_birth_year_candidates(entity)
        resolved = birth_info_records(entity).filter_map do |record|
          year = extract_year_from_date(record['date'] || record['year'])
          [year, record['circa'] == true] if year
        end
        return nil if resolved.empty?

        candidates = resolved.map(&:first).uniq.sort
        if candidates.size == 1
          circa = resolved.any? { |year, circa_flag| year == candidates.first && circa_flag }
          return { kind: 'exact', years: candidates, circa: circa }
        end

        circa = resolved.any? { |_year, circa_flag| circa_flag }
        { kind: 'candidates', years: candidates, circa: circa }
      end

      # The legacy flat fields, read only when no birthInfo record named
      # anything at all. Neither field carries a circa flag.
      # @param entity [Hash] entity data
      # @return [Hash, nil]
      def extract_birth_year_fallback(entity)
        year = extract_year_from_date(entity['birthDate']) || extract_year_from_date(entity['birth_date'])
        return nil unless year

        { kind: 'exact', years: [year], circa: false }
      end

      # @param entity [Hash] entity data
      # @return [Hash, nil] the first birth record stating either bound
      def birth_info_with_range(entity)
        birth_info_records(entity).find do |birth|
          (BIRTH_YEAR_FROM_KEYS + BIRTH_YEAR_TO_KEYS)
            .any? { |key| scalar_presence(birth[key]) }
        end
      end

      # @param entity [Hash] entity data
      # @return [Array<Hash>] birth records, in either key spelling
      def birth_info_records(entity)
        %w[birth_info birthInfo].each do |key|
          list = entity[key]
          next unless list.is_a?(Array)

          records = list.grep(Hash)
          return records unless records.empty?
        end
        []
      end

      # Extract year from date (handles both String and Date objects)
      # @param date [String, Date, nil] date value
      # @return [String, nil] year as string
      # A valid year: exactly four digits. Every caller in this file now
      # feeds unfiltered source values straight to this method (the old
      # single-record `birthYear` path was the only one, and #build_row
      # ran the result through #string_presence to catch blanks itself);
      # candidate extraction has no such filter downstream, so a boolean
      # or a Hash's #to_s ("true", "{\"ba...") must be rejected HERE
      # rather than published as a "year".
      # @param date [String, Date, Time, DateTime, Object, nil] candidate
      # @return [String, nil] a well-formed four-digit year, or nil
      def extract_year_from_date(date)
        return nil unless date

        year =
          case date
          when String
            date[0, 4] if date.length >= 4
          when Date, DateTime, Time
            date.year.to_s
          else
            date.to_s[0, 4] if date.to_s.length >= 4
          end

        year if year&.match?(FOUR_DIGIT_YEAR)
      end

      # A stated span's bound, validated the same way a candidate year
      # is. Codex review finding (2026-09-14, round 2): the span path
      # used to accept whatever #scalar_presence let through, so a
      # malformed bound ("bad") both published as a "year" AND, by
      # winning precedence over the candidates path, suppressed a
      # perfectly good year another record in the SAME entity stated.
      # @param value [Object] candidate bound value
      # @return [String, nil]
      def valid_year_bound(value)
        candidate = scalar_presence(value)
        candidate if candidate&.match?(FOUR_DIGIT_YEAR)
      end

      # Extract IMO number from entity (vessels)
      # @param entity [Hash] entity data
      # @return [String, nil] IMO number
      def extract_imo(entity)
        entity_type = entity['entityType'] || entity['entity_type']
        return nil unless entity_type == 'vessel'

        # From identifiers, then identifications (snake_case)
        %w[identifiers identifications].each do |key|
          value = imo_from_identifiers(entity[key])
          return value if value
        end

        # From imo field
        entity['imo'] || entity['imoNumber'] || entity['imo_number']
      end

      # Find the IMO value in one identifier collection
      # @param identifiers [Object] candidate identifier collection
      # @return [Object, nil] raw IMO value (coerced by #scalar_presence)
      def imo_from_identifiers(identifiers)
        return nil unless identifiers.is_a?(Array)

        imo = identifiers.find { |id| id.is_a?(Hash) && imo_identifier?(id) }
        return nil unless imo

        imo['value'] || imo['identification']
      end

      # Whether an identifier is an IMO number. The type discriminator
      # takes the String rule: #downcase on a wrong-typed source value
      # would raise NoMethodError instead of skipping the identifier
      # @param identifier [Hash] identifier hash
      # @return [Boolean]
      def imo_identifier?(identifier)
        %w[type document_type].any? do |key|
          string_presence(identifier[key])&.downcase == 'imo'
        end
      end

      # Export source-sharded search indexes.
      # @param output_dir [String] output directory
      def export_search_index(output_dir)
        rows = entities
        generated = Time.now.utc.iso8601
        search_index_dir = File.join(output_dir, 'search-index')

        # A reused output directory must not carry stale output forward:
        # a pre-sharding monolithic search-index.json, or a shard file for
        # an authority that produced rows on a previous run but not this
        # one. Wiping the shard directory before writing is simpler and
        # safer than diffing old contents against the new shard set.
        FileUtils.rm_f(File.join(output_dir, 'search-index.json'))
        FileUtils.rm_rf(search_index_dir)
        FileUtils.mkdir_p(search_index_dir)

        # Group the already-finalized rows once, then serialize each group.
        # Do not build a monolithic payload and split it afterward.
        rows_by_source = rows.group_by { |row| row[:authority] }
        shards = rows_by_source.map do |authority, source_rows|
          code = shard_code(authority)

          File.write(
            File.join(search_index_dir, "#{code}.json"),
            JSON.generate(
              search_index_data(
                source_rows,
                generated,
                authority ? 1 : 0
              )
            )
          )

          {
            code: code,
            file: "#{code}.json",
            count: source_rows.length
          }
        end

        export_search_index_manifest(
          search_index_dir,
          generated: generated,
          total_entities: rows.length,
          source_count: rows_by_source.keys.compact.length,
          shards: shards
        )

        puts "Exported search index: #{rows.length} entities across " \
             "#{shards.length} shards to #{search_index_dir}"
      end

      # Turn an authority into the path component its shard file is named
      # after. The authority value now reaches a filename (it previously
      # only fed in-memory facet counts), so anything outside a strict
      # allowlist falls back to 'unknown' rather than being interpolated
      # as-is: an authority carrying '/', '..', or a null byte must never
      # let a shard escape the search-index directory.
      # @param authority [String, nil] raw (already-downcased) authority
      # @return [String] a safe shard filename stem
      def shard_code(authority)
        return 'unknown' unless authority.is_a?(String)
        return 'unknown' unless authority.match?(/\A[a-z0-9_-]+\z/)

        authority
      end

      # Build one shard's payload using the existing search-index shape.
      # @param rows [Array<Hash>] rows belonging to one authority
      # @param generated [String] shared export timestamp
      # @param source_count [Integer] number of authorities represented
      # @return [Hash]
      def search_index_data(rows, generated, source_count)
        {
          metadata: {
            generated: generated,
            totalEntities: rows.length,
            sources: source_count
          },
          entities: rows
        }
      end

      # Write the manifest used to discover the shard files.
      # `file` is relative to the search-index directory.
      # @param dir [String] search-index directory
      # @param generated [String] shared export timestamp
      # @param total_entities [Integer] total deduplicated rows
      # @param source_count [Integer] number of non-empty authority groups
      # @param shards [Array<Hash>] shard descriptors
      # @return [void]
      def export_search_index_manifest(dir, generated:, total_entities:,
                                       source_count:, shards:)
        manifest = {
          metadata: {
            generated: generated,
            totalEntities: total_entities,
            sources: source_count
          },
          shards: shards.sort_by { |shard| shard[:code] }
        }

        File.write(
          File.join(dir, 'manifest.json'),
          JSON.generate(manifest)
        )
      end

      # Export facet files
      # @param output_dir [String] output directory
      def export_facets(output_dir)
        facets_dir = File.join(output_dir, 'facets')
        FileUtils.mkdir_p(facets_dir)

        counts = build_facets

        export_authority_facets(facets_dir, counts)
        export_list_type_facets(facets_dir, counts)
        export_regime_facets(facets_dir, counts)
        export_type_facets(facets_dir, counts)
        export_country_facets(facets_dir, counts)
        export_status_facets(facets_dir, counts)
      end

      # Export authority facets
      # @param dir [String] facets directory
      # @param counts [Hash] facet counts
      def export_authority_facets(dir, counts)
        facets_data = counts[:authorities].map do |code, count|
          {
            code: code,
            name: AUTHORITY_NAMES[code] || code.upcase,
            count: count
          }
        end.sort_by { |f| -f[:count] }

        File.write(File.join(dir, 'authorities.json'), JSON.generate(facets: facets_data))
      end

      # Export list type facets
      # @param dir [String] facets directory
      # @param counts [Hash] facet counts
      def export_list_type_facets(dir, counts)
        facets_data = counts[:list_types].map do |code, count|
          {
            code: code,
            name: format_list_type_name(code),
            count: count
          }
        end.sort_by { |f| -f[:count] }

        File.write(File.join(dir, 'list_types.json'), JSON.generate(facets: facets_data))
      end

      # Format list type code into display name
      # @param code [String] list type code
      # @return [String] formatted name
      def format_list_type_name(code)
        code.to_s
            .gsub('-', ' ')
            .split
            .map(&:capitalize)
            .join(' ')
      end

      # Export regime facets
      # @param dir [String] facets directory
      # @param counts [Hash] facet counts
      def export_regime_facets(dir, counts)
        facets_data = counts[:regimes].map do |code, data|
          {
            code: code,
            name: data[:name] || code.upcase,
            count: data[:count]
          }
        end.sort_by { |f| -f[:count] }

        File.write(File.join(dir, 'regimes.json'), JSON.generate(facets: facets_data))
      end

      # Export type facets
      # @param dir [String] facets directory
      # @param counts [Hash] facet counts
      def export_type_facets(dir, counts)
        facets_data = counts[:types].map do |code, count|
          type_info = ENTITY_TYPES[code] || { name: code.capitalize, icon: 'circle' }
          {
            code: code,
            name: type_info[:name],
            icon: type_info[:icon],
            count: count
          }
        end.sort_by { |f| -f[:count] }

        File.write(File.join(dir, 'types.json'), JSON.generate(facets: facets_data))
      end

      # Export country facets
      # @param dir [String] facets directory
      # @param counts [Hash] facet counts
      def export_country_facets(dir, counts)
        facets_data = counts[:countries].map do |code, count|
          {
            code: code,
            count: count
          }
        end.sort_by { |f| -f[:count] }

        File.write(File.join(dir, 'countries.json'), JSON.generate(facets: facets_data))
      end

      # Export status facets
      # @param dir [String] facets directory
      # @param counts [Hash] facet counts
      def export_status_facets(dir, counts)
        facets_data = counts[:statuses].map do |code, count|
          {
            code: code,
            name: code.capitalize,
            count: count
          }
        end.sort_by { |f| -f[:count] }

        File.write(File.join(dir, 'statuses.json'), JSON.generate(facets: facets_data))
      end
    end
  end
end
