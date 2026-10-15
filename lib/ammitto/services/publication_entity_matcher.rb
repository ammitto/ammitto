# frozen_string_literal: true

require 'date'

module Ammitto
  module Services
    # Conservative cross-source identity links. Source nodes are never merged.
    # Candidate blocks are bounded; names alone are review leads, not identity.
    class PublicationEntityMatcher
      MAX_BLOCK_SIZE = 50
      MAX_REVIEW_CANDIDATES = 1000
      MAX_REVIEW_COMPARISONS = 20_000
      # ISO 3166-1 assigned alpha-2 codes; unknown/user-assigned issuers do not qualify.
      ISSUER_COUNTRIES = %w[
        AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE
        BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ CA CC CD
        CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM
        DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR GA GB GD GE GF
        GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU
        ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN
        KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME
        MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ NA
        NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM
        PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI
        SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK
        TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI
        VN VU WF WS YE YT ZA ZM ZW
      ].freeze
      IDENTIFIER_TYPES = {
        'passport' => 'passport', 'nationalid' => 'national_id',
        'diplomaticpassport' => 'diplomatic_passport',
        'taxid' => 'tax_id'
      }.freeze
      ENTITY_TYPES = %w[PersonEntity OrganizationEntity VesselEntity AircraftEntity].freeze

      attr_reader :review_candidates, :matches, :skipped_blocks, :candidate_pairs_count, :review_comparisons, :review_truncated

      def initialize
        @review_candidates = []
        @matches = []
        @skipped_blocks = 0
      end

      # @param records [Array<Hash>] { node: serialized_entity, source: code }
      # @return [Array<Hash>] published pair evidence; mutates only sameAs
      def resolve!(records)
        @review_candidates = []
        @matches = []
        @skipped_blocks = 0
        rows = records.filter_map { |record| prepare(record) }.sort_by { |row| row[:id] }
        pairs = candidate_pairs(rows)
        @candidate_pairs_count = pairs.length
        edges = {}
        pairs.each do |left, right|
          a = rows[left]
          b = rows[right]
          next if a[:source] == b[:source] || conflict?(a, b)

          evidence = evidence_for(a, b)
          edges[[left, right]] = evidence if evidence
        end
        publish_components(rows, edges)
        find_review_candidates(rows, @matches.to_set { |match| match[:ids] })
        @matches
      end

      private

      def prepare(record)
        node = record[:node]
        return unless node.is_a?(Hash) && ENTITY_TYPES.include?(node['@type'])
        return unless node['@id'].is_a?(String) && !record[:source].to_s.empty?

        { node: node, id: node['@id'], source: record[:source].to_s,
          type: node['@type'], names: names(node), dates: dates(node), identifiers: identifiers(node) }
      end

      def names(node)
        Array(node['names']).filter_map do |name|
          next unless name.is_a?(Hash) && name['fullName'].is_a?(String)

          text = name['fullName'].unicode_normalize(:nfc).downcase.gsub(/[^\p{L}\p{N}]+/, ' ').strip
          words = text.split
          words.sort.join(' ') if words.length >= 2 && text.length >= 10
        end.uniq
      end

      def dates(node)
        Array(node['birthInfo']).filter_map do |birth|
          next unless birth.is_a?(Hash) && (birth['date'].is_a?(String) || birth['date'].is_a?(Date))

          value = birth['date'].to_s
          next if birth['circa'] || %w[dateRangeFrom dateRangeTo yearRangeFrom yearRangeTo].any? { |key| birth[key] }
          next unless value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

          Date.iso8601(value).iso8601
        rescue Date::Error
          nil
        end.uniq
      end

      def identifiers(node)
        result = Array(node['identifications']).filter_map do |identifier|
          next unless identifier.is_a?(Hash)

          type = IDENTIFIER_TYPES[identifier['type'].to_s.downcase.gsub(/[^a-z]/, '')]
          next unless type

          country = identifier['countryIsoCode'].to_s.upcase
          stated_country = identifier['issuingCountry'].to_s.upcase
          next if !country.empty? && ISSUER_COUNTRIES.include?(stated_country) && country != stated_country

          country = stated_country if country.empty?
          number = identifier['number'].to_s.upcase.gsub(/[ -]/, '')
          next unless ISSUER_COUNTRIES.include?(country) && number.match?(/\A[A-Z0-9]{5,30}\z/)
          next if number.match?(/\A(?:UNKNOWN|NONE|NOTAVAILABLE|0+|X+)\z/)

          [type, country, number]
        end
        imo = node['imoNumber'].to_s.delete_prefix('IMO').strip
        result << ['imo', '', imo] if node['@type'] == 'VesselEntity' && valid_imo?(imo)
        result.uniq
      end

      def valid_imo?(number)
        return false unless number.match?(/\A\d{7}\z/) && number != '0000000'

        number.chars.first(6).each_with_index.sum { |digit, index| digit.to_i * (7 - index) } % 10 == number[-1].to_i
      end

      def candidate_pairs(rows)
        blocks = Hash.new { |hash, key| hash[key] = [] }
        rows.each_with_index do |row, index|
          keys = row[:identifiers].map { |id| [:identifier, row[:type], *id] }
          keys.concat(row[:dates].map { |date| [:birth, row[:type], date] })
          keys.uniq.each do |key|
            # Keep only a sentinel after a block exceeds its safe bound.
            blocks[key] << index if blocks[key].length <= MAX_BLOCK_SIZE
          end
        end
        pairs = Set.new
        blocks.each_value do |indices|
          if indices.length > MAX_BLOCK_SIZE
            @skipped_blocks += 1
            next
          end
          indices.combination(2) { |a, b| pairs << [a, b] }
        end
        pairs.sort
      end

      # Review sampling has its own global work budget. It cannot consume or
      # truncate the strong identifier/date candidate pass above.
      def find_review_candidates(rows, published_pairs)
        @review_comparisons = 0
        @review_truncated = false
        blocks = Hash.new { |hash, key| hash[key] = [] }
        rows.each_with_index do |row, index|
          row[:names].flat_map(&:split).uniq.sort.each do |word|
            key = [row[:type], word]
            blocks[key] << index if blocks[key].length <= MAX_BLOCK_SIZE
          end
        end
        seen = Set.new
        blocks.each_value do |indices|
          if indices.length > MAX_BLOCK_SIZE
            @skipped_blocks += 1
            next
          end
          indices.combination(2) do |left, right|
            if @review_comparisons >= MAX_REVIEW_COMPARISONS || @review_candidates.length >= MAX_REVIEW_CANDIDATES
              @review_truncated = true
              return @review_candidates
            end
            @review_comparisons += 1
            next unless seen.add?([left, right])

            a = rows[left]
            b = rows[right]
            next if published_pairs.include?([a[:id], b[:id]])
            next if a[:source] == b[:source] || conflict?(a, b) || !similar_names?(a, b)

            @review_candidates << { ids: [a[:id], b[:id]], reason: 'name_similarity_requires_review' }
          end
        end
      end

      def conflict?(left, right)
        return true if left[:type] != right[:type]
        return true if left[:dates].any? && right[:dates].any? && left[:dates].sort != right[:dates].sort

        left[:identifiers].group_by { |id| id.first(2) }.any? do |scope, identifiers|
          other = right[:identifiers].select { |id| id.first(2) == scope }
          other.any? && (identifiers & other).empty?
        end
      end

      def evidence_for(left, right)
        shared = left[:identifiers] & right[:identifiers]
        return 'qualified_identifier' if shared.any?
        return unless left[:type] == 'PersonEntity' && left[:dates].length == 1 && left[:dates] == right[:dates] && similar_names?(left, right)

        'full_birth_date_and_name'
      end

      def similar_names?(left, right)
        left[:names].any? { |left_name| right[:names].any? { |right_name| one_edit_apart?(left_name, right_name) } }
      end

      # A deliberately narrow fuzzy comparison: one insertion/deletion/substitution.
      def one_edit_apart?(left, right)
        return true if left == right
        return false if (left.length - right.length).abs > 1

        a = left.chars
        b = right.chars
        a, b = b, a if a.length > b.length
        i = 0
        j = 0
        edits = 0
        while i < a.length && j < b.length
          if a[i] == b[j]
            i += 1
          else
            edits += 1
            return false if edits > 1

            i += 1 if a.length == b.length
          end
          j += 1
        end
        edits + (b.length - j) <= 1
      end

      def publish_components(rows, edges)
        adjacent = Hash.new { |hash, key| hash[key] = [] }
        edges.each_key do |left, right|
          adjacent[left] << right
          adjacent[right] << left
        end
        visited = Set.new
        adjacent.each_key do |start|
          next if visited.include?(start)

          component = []
          pending = [start]
          until pending.empty?
            index = pending.pop
            next unless visited.add?(index)

            component << index
            pending.concat(adjacent[index])
          end
          # owl:sameAs is transitive. Require a complete compatible clique,
          # with one record per source, rather than bridging weak chains.
          sources = component.map { |index| rows[index][:source] }
          next unless sources.uniq.length == sources.length
          next unless component.combination(2).all? { |a, b| edges.key?([a, b].sort) }

          component.combination(2) do |a, b|
            left = rows[a]
            right = rows[b]
            link(left[:node], right[:id])
            link(right[:node], left[:id])
            @matches << { ids: [left[:id], right[:id]].sort, evidence: edges.fetch([a, b].sort) }
          end
        end
      end

      def link(node, id)
        node['sameAs'] = (Array(node['sameAs']) + [id]).uniq.sort
      end
    end
  end
end
