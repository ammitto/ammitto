# frozen_string_literal: true

require 'lutaml/model'
require 'roo'
require_relative '../../utils/iri_sanitizer'

module Ammitto
  module Sources
    module Tr
      # Raised when the workbook cannot be turned into records without
      # losing or misattributing one of them.
      #
      # Every condition that raises here is a case where continuing would
      # publish a corpus that is quietly wrong: a column silently
      # overwriting another column, two designees silently minting one
      # IRI, or a reserved IRI silently changing which designee it
      # denotes. Parsing completes before any of it is written, so a
      # refused harvest names the offending record and leaves the
      # previous corpus untouched.
      class IntegrityError < StandardError; end

      # Turkey sanctions source models
      #
      # Turkey has 4 sanction lists:
      # - List A: Article 5, Law No.6415 (UNSC resolutions) - DOCX
      # - List B: Article 6, Law No.6415 - ?
      # - List C: Article 7, Law No.6415 - ?
      # - List D: Law No.7262, Articles 3.A/3.B - XLSX
      #
      # The extractor currently handles List D (XLSX format).
      #

      # Sanctioned entity from Turkey List D
      class SanctionedEntity < Lutaml::Model::Serializable
        attribute :name, :string
        attribute :entity_type, :string # Individual, Entity
        attribute :program, :string
        attribute :remarks, :string
        attribute :listed_date, :string
        attribute :reference_number, :string

        # Person-specific fields
        attribute :date_of_birth, :string
        attribute :place_of_birth, :string
        attribute :nationality, :string
        attribute :passport_number, :string
        attribute :national_id, :string

        # Organization-specific fields
        attribute :registration_number, :string
        attribute :address, :string

        # Publication provenance. Turkey cites the Official Gazette issue
        # that carried the listing and the Presidential Decree (BKK/CBK)
        # that ordered it, in two columns of their own. Both were
        # previously swallowed by the header mapping; the decree number is
        # what used to be stored, wrongly, as +listed_date+.
        attribute :official_gazette, :string
        attribute :decision_number, :string

        yaml do
          map 'name', to: :name
          map 'entity_type', to: :entity_type
          map 'program', to: :program
          map 'remarks', to: :remarks
          map 'listed_date', to: :listed_date
          map 'reference_number', to: :reference_number
          map 'date_of_birth', to: :date_of_birth
          map 'place_of_birth', to: :place_of_birth
          map 'nationality', to: :nationality
          map 'passport_number', to: :passport_number
          map 'national_id', to: :national_id
          map 'registration_number', to: :registration_number
          map 'address', to: :address
          map 'official_gazette', to: :official_gazette
          map 'decision_number', to: :decision_number
        end

        # References whose IRI is already published for a named designee.
        #
        # Turkey assigns "Sıra No" 187 to two different organisations, so
        # the number alone does not identify a record. One of the two is
        # already published as entity/tr/187 and the other has never been
        # published at all, but nothing in the workbook says which — the
        # payload carries row order and content, never publication
        # history. This table supplies exactly that missing fact, keyed by
        # the sanitized name of the designee the IRI already denotes.
        #
        # Read it as a reservation, not a tie-break: it is evaluated
        # whenever the reference appears, duplicated or not. A rule that
        # only fired on a duplicate would have a hole — if Turkey
        # renumbered the published holder and left the other row on 187,
        # no duplicate would remain, the rule would never fire, and a live
        # IRI would quietly change which organisation it denotes.
        #
        # Deliberately narrow: this protects specific pre-existing IRIs.
        # It is not a general identifier-stability system, which would
        # need a durable ledger of every id ever published.
        RESERVED_LOCAL_IDS = {
          '187' => 'defense-technology-and-science-research-enter-dtsrc'
        }.freeze

        def person?
          entity_type&.downcase == 'individual'
        end

        def organization?
          entity_type&.downcase == 'entity'
        end

        # Local identifier this record's IRIs and filename are minted
        # from.
        #
        # Normally Turkey's own "Sıra No", exactly as +reference_number+
        # carries it. Where that number is reserved for a different
        # designee (see RESERVED_LOCAL_IDS), the record falls back to its
        # name instead, so both designees survive as distinct records
        # rather than the later one overwriting the earlier.
        #
        # The raw value is returned rather than a pre-slugged one, because
        # the IRI layer sanitizes whatever it is given.
        #
        # Deliberately no opinion on what a well-formed reference looks
        # like: this method changes identity only where a reservation
        # applies, and SanctionsList.verify_distinct_local_ids! catches
        # any reference whose sanitized form lands on another record.
        # PR #31 (fix/tr-reference-backfill) is where the shape of an
        # acceptable reference is being decided.
        #
        # @return [String, nil] the local id, or nil when Turkey published
        #   no reference for this record
        def local_id
          reference = reference_number.to_s.strip

          # Turkey leaves "Sıra No" blank for part of List D. Those rows
          # have no local id, which the IRI layer reports as a missing
          # identifier. PR #31 changes this single line to fall back to
          # the name; that change composes with the reservation below.
          return nil if reference.empty?

          holder = RESERVED_LOCAL_IDS[reference]
          return reference if holder.nil? || sanitized_name == holder

          fallback_name
        end

        private

        # The record name, used when the record cannot take its own
        # number.
        #
        # Refused when it would sanitize to a bare integer, because bare
        # integers are Turkey's own numbering namespace. This makes it
        # structurally impossible for a name-derived id to occupy a slot
        # Turkey assigned to a different designee.
        #
        # @return [String, nil]
        def fallback_name
          str = name.to_s.strip
          return nil if str.empty?
          return nil if sanitized_name.match?(/\A\d+\z/)

          str
        end

        # @return [String] the name as the IRI layer would slug it
        def sanitized_name
          Utils::IriSanitizer.sanitize(name.to_s)
        end
      end

      # Alias for backward compatibility with harmonize command
      Entity = SanctionedEntity

      # Collection of sanctioned entities from Turkey
      class SanctionsList < Lutaml::Model::Serializable
        attribute :entities, SanctionedEntity, collection: true

        yaml do
          map 'entities', to: :entities
        end

        # Row fields the parser reads. Only these are guarded against
        # header collapse: a symbol nothing consumes can be produced
        # twice (by two blank header cells, say) without costing data.
        CONSUMED_FIELDS = %i[
          reference_number name organization_name former_name aliases
          passport_number title address nationality listed_date remarks
          place_of_birth mother_name father_name date_of_birth
          official_gazette decision_number
        ].freeze

        # Parse from XLSX file
        # @param xlsx_path [String] path to XLSX file
        # @return [SanctionsList]
        # @raise [IntegrityError] when the sheet cannot be parsed without
        #   losing or misattributing a record
        def self.from_xlsx(xlsx_path)
          sheet = Roo::Excelx.new(xlsx_path).sheet(0)
          headers = header_fields(sheet)

          entities = (2..sheet.last_row).filter_map do |row_num|
            build_entity(read_row(sheet, row_num, headers))
          end

          verify_reservations!(entities)
          verify_mintable_local_ids!(entities)
          verify_distinct_local_ids!(entities)

          new(entities: entities)
        end

        # Normalized header symbols, one per column.
        #
        # Two columns landing on one field is refused rather than
        # tolerated: the row builder assigns by field, so the rightmost
        # column would silently overwrite every column to its left. That
        # is precisely how four separate date columns once collapsed onto
        # +listed_date+, leaving every record carrying a decree number
        # where its listing date belonged.
        #
        # @param sheet [Roo::Excelx::Sheet]
        # @return [Array<Symbol>]
        # @raise [IntegrityError] when two columns map to one field
        def self.header_fields(sheet)
          headers = sheet.row(1).map { |h| normalize_header(h) }
          collapsed = headers.tally.select do |field, count|
            count > 1 && CONSUMED_FIELDS.include?(field)
          end
          return headers if collapsed.empty?

          raise IntegrityError,
                'tr: header columns collapse onto one field — ' \
                "#{describe_collapse(sheet, headers, collapsed.keys)}"
        end

        # @return [String] human-readable collapse report
        def self.describe_collapse(sheet, headers, fields)
          row = sheet.row(1)
          fields.map do |field|
            columns = headers.each_index.select { |i| headers[i] == field }
            titles = columns.map { |i| row[i].to_s.gsub(/\s+/, ' ').strip }
            "#{field} <- #{titles.map(&:inspect).join(', ')}"
          end.join('; ')
        end

        # Read one sheet row into a field-keyed hash
        # @return [Hash{Symbol => String, nil}]
        def self.read_row(sheet, row_num, headers)
          values = sheet.row(row_num)

          headers.each_with_index.to_h do |field, idx|
            val = values[idx]
            [field, val.is_a?(Date) ? val.iso8601 : val&.to_s&.strip]
          end
        end

        # Build one entity from a parsed row
        # @param row [Hash{Symbol => String, nil}]
        # @return [SanctionedEntity, nil] nil when the row carries no name
        def self.build_entity(row)
          # Name could be in 'name' (individual) or 'organization_name'
          name = row[:name] || row[:organization_name] || row[:former_name]
          return nil if name.nil? || name.empty?

          SanctionedEntity.new(
            name: name,
            entity_type: detect_entity_type(row),
            program: 'Law No. 7262, Articles 3.A/3.B',
            remarks: row[:remarks] || row[:aliases] || row[:title],
            listed_date: row[:listed_date],
            reference_number: row[:reference_number],
            date_of_birth: row[:date_of_birth],
            place_of_birth: row[:place_of_birth],
            nationality: row[:nationality],
            passport_number: row[:passport_number],
            national_id: nil,
            registration_number: nil,
            address: row[:address],
            official_gazette: row[:official_gazette],
            decision_number: row[:decision_number]
          )
        end

        # Check every reserved reference still denotes the designee its
        # published IRI was minted for.
        #
        # Five outcomes, and only two of them are quiet. The holder is
        # identified by name, so the check is independent of row order,
        # and it runs whether or not the reference is duplicated.
        #
        # @param entities [Array<SanctionedEntity>]
        # @raise [IntegrityError] when the reservation no longer resolves
        def self.verify_reservations!(entities)
          SanctionedEntity::RESERVED_LOCAL_IDS.each do |reference, slug|
            holders = entities.select do |entity|
              Utils::IriSanitizer.sanitize(entity.name.to_s) == slug
            end
            claimants = entities.select do |entity|
              entity.reference_number.to_s.strip == reference
            end

            check_reservation!(reference, slug, holders, claimants)
          end
        end

        # @raise [IntegrityError] unless the reservation resolves cleanly
        def self.check_reservation!(reference, slug, holders, claimants)
          if holders.size > 1
            raise IntegrityError, reservation_error(
              reference, "#{holders.size} rows share the reserved name " \
                         "#{slug.inspect}, so it no longer identifies one record"
            )
          end

          return if holders.empty? && claimants.empty? # delisted: inert

          if holders.empty?
            raise IntegrityError, reservation_error(
              reference, "no row carries the reserved name #{slug.inspect}, " \
                         'but another row claims the reference'
            )
          end

          return if claimants.any? { |claimant| claimant.equal?(holders.first) }

          raise IntegrityError, reservation_error(
            reference, "the reserved name #{slug.inspect} now carries " \
                       "reference #{holders.first.reference_number.inspect}"
          )
        end

        # @return [String] reservation failure message
        def self.reservation_error(reference, detail)
          "tr: reserved reference #{reference.inspect} no longer resolves " \
            "— #{detail}. entity/tr/#{reference} is published; refusing to " \
            'republish it for a different designee. A human must decide ' \
            'which record keeps it.'
        end

        # Refuse a record carrying a reference that mints no IRI at all.
        #
        # Turkey publishing a reference is a claim that the record has an
        # identifier. When that reference survives sanitization as
        # nothing — punctuation alone, say — the claim is false: the IRI
        # layer refuses it rather than emit a shared ".../unknown", so the
        # record cannot become a graph node. Fetch would still write it to
        # disk under a filename of hyphens and report the source
        # succeeded, and only harmonize would discover it.
        #
        # Caught here instead, where the whole workbook is in hand and
        # nothing has been written yet: the source fails, names the
        # record, and leaves the previous corpus in place.
        #
        # This is not a rule about what a well-formed reference looks
        # like — it defers entirely to what Utils::IriSanitizer already
        # accepts. A record with no reference at all is untouched: it has
        # made no claim to identify itself, and SanctionedEntity#local_id
        # is where that case is decided.
        #
        # @param entities [Array<SanctionedEntity>]
        # @raise [IntegrityError] when a present reference mints nothing
        def self.verify_mintable_local_ids!(entities)
          unusable = entities.select do |entity|
            id = entity.local_id
            !id.nil? && mintable_id(id).nil?
          end
          return if unusable.empty?

          raise IntegrityError,
                'tr: record carries an identifier that mints no IRI — ' \
                "#{describe_unmintable(unusable)}"
        end

        # @param entities [Array<SanctionedEntity>] offending records
        # @return [String] human-readable report
        def self.describe_unmintable(entities)
          entities.map do |entity|
            "#{entity.local_id.to_s.inspect} " \
              "(#{entity.name.to_s.inspect})"
          end.join('; ')
        end

        # Refuse two records that would mint one IRI.
        #
        # The terminating rule for the name fallback: a name-derived id is
        # not automatically unique either, and two names sharing their
        # first 64 sanitized characters collide just as two equal
        # references do. Raising surfaces the record; an ordinal suffix
        # would bury it behind an id that moves with row order.
        #
        # @param entities [Array<SanctionedEntity>]
        # @raise [IntegrityError] when two records share a sanitized id
        def self.verify_distinct_local_ids!(entities)
          by_id = entities.group_by { |entity| mintable_id(entity.local_id) }
          by_id.delete(nil)
          collisions = by_id.select { |_id, rows| rows.size > 1 }
          return if collisions.empty?

          raise IntegrityError,
                'tr: distinct records mint one identifier — ' \
                "#{describe_collisions(collisions)}"
        end

        # The identifier this record would actually mint, or nil when it
        # would mint none.
        #
        # Deliberately the IRI layer's own strict sanitizer rather than
        # Utils::IriSanitizer.sanitize. The lenient one answers "unknown"
        # for an id that sanitizes to nothing, which files a record under
        # a key it can never own — and collides it with a record whose id
        # really does slug to "unknown", reporting a shared identifier
        # between one record that mints that IRI and one that mints no
        # IRI at all. Grouping on what the IRI layer will really produce
        # keeps this gate's verdict and the IRI layer's verdict the same
        # verdict.
        #
        # An id that mints nothing is the same case as a nil id here:
        # there is no identifier for it to be distinct from, so it leaves
        # the grouping the way nil does. In a parse it never reaches this
        # method — verify_mintable_local_ids! has already failed the
        # source — but this gate is called directly too, and distinctness
        # is not the place to report an unusable id.
        #
        # This method has no opinion on what a well-formed reference
        # looks like — see SanctionedEntity#local_id.
        #
        # @param local_id [Object, nil] the record's local id
        # @return [String, nil] the identifier it mints, or nil for none
        def self.mintable_id(local_id)
          return nil if local_id.nil?

          Utils::IriSanitizer.sanitize_local_id!(local_id, source: 'tr',
                                                           kind: 'entity')
        rescue Utils::IriSanitizer::MissingLocalIdError
          nil
        end

        # @return [String] human-readable collision report
        def self.describe_collisions(collisions)
          collisions.map do |id, rows|
            names = rows.map { |row| row.name.to_s.inspect }.join(', ')
            "#{id.inspect} <- #{names}"
          end.join('; ')
        end

        # Detect entity type from row data
        def self.detect_entity_type(row)
          # If organization_name column has data, it's an organization
          if row[:organization_name] && !row[:organization_name].empty?
            'organization'
          # If name column has data (individual name column), it's a person
          elsif row[:name] && !row[:name].empty?
            'person'
          # Check other indicators
          elsif row[:date_of_birth] || row[:place_of_birth] || row[:mother_name] || row[:father_name]
            'person'
          else
            'organization'
          end
        end

        # Normalize header to symbol.
        #
        # The cleanup strips every non-ASCII character, so a pattern has
        # to match the header as it survives that: "Uyruğu" arrives as
        # "uyruu", with no letter where its "ğ" was. Patterns therefore
        # match the stem and let +.*+ absorb what was stripped.
        #
        # Order is load-bearing. Four of Turkey's columns are dated —
        # "Listeye Alınma Tarihi", "Doğum Tarihi", "R.Gazete Tarih Sayı"
        # and "BKK-CBK Karar Tarih ve Sayısı" — so every specific pattern
        # must be tested before anything that matches "tarih" broadly, and
        # /gazete/ before the /rg.*t/ that "rgazete" also satisfies.
        # Getting this order wrong does not fail: it silently maps
        # distinct columns onto one field, which #header_fields now
        # refuses.
        def self.normalize_header(header)
          return :unknown if header.nil?

          # Clean up header - remove newlines, extra spaces
          h = header.to_s.strip.gsub(/\s+/, ' ').gsub(/[^a-z0-9_\s]/i, '').downcase

          # Map common Turkish/English headers
          case h
          when /s.*ra.*no/, /sira.*no/ then :reference_number
          when /ger.*ek.*ki.*i/, /soyad/, /gercek/ then :name
          when /t.*zel.*kurulu/, / organizasyon/, /tuze/ then :organization_name
          when /eski.*ad/ then :former_name
          when /kulland.*di.*er/, /bilinen.*di.*er/ then :aliases
          when /pasaport/, /muhtelif/ then :passport_number
          when /g.*rev/ then :title
          when /adres/ then :address
          when /uyru/ then :nationality
          when /di.*er.*bilgi/ then :remarks
          when /do.*um.*yer/ then :place_of_birth
          when /anne.*ad/ then :mother_name
          when /baba.*ad/ then :father_name
          when /do.*um.*tarih/ then :date_of_birth
          when /gazete/ then :official_gazette
          when /bkk.*cbk/, /karar/ then :decision_number
          when /.*rg.*t/ then :organization
          when /listeye.*al.*nma/ then :listed_date
          else
            # Generate symbol from cleaned header
            h.gsub(/\s+/, '_').to_sym
          end
        end

        def count
          entities.size
        end
      end
    end
  end
end
