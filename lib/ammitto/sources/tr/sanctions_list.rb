# frozen_string_literal: true

require 'date'
require 'lutaml/model'
require 'roo'
require_relative '../../utils/iri_sanitizer'
require_relative 'integrity_error'
require_relative 'sanctioned_entity'

module Ammitto
  module Sources
    module Tr
      # The four Turkish lists, which law each falls under and which one
      # the extractor actually handles are in lib/ammitto/sources/tr.rb.
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

          entities = collapse_duplicate_rows(
            (2..sheet.last_row).filter_map do |row_num|
              build_entity(read_row(sheet, row_num, headers))
            end
          )

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
            [field, cell_text(values[idx])]
          end
        end

        # Text of one sheet cell, as the record should carry it.
        #
        # The first of the two roads a reference travels: writing the
        # canonical spelling here means every consumer of a freshly
        # fetched record — the filename, the harmonized source reference,
        # the IRI — sees one number rather than the display format's
        # rendering of it. SanctionedEntity.exact_integer_text carries this
        # road's rule and the reasoning behind both;
        # SanctionedEntity#local_id covers the other road, the record file
        # harmonize re-reads, where the artefact is text rather than a
        # Float and the rule differs accordingly.
        #
        # Applied to every column rather than to the reference alone, so a
        # passport, gazette or decision number Turkey reformats the same
        # way is read the same way. Only a Float is touched: a text cell
        # is workbook text, and rewriting it here would corrupt an
        # identifier Turkey actually wrote. Anything else — a fractional
        # Float, a Float too large to be provably exact, a string, a date
        # — falls through to the text it has always had.
        #
        # @param value [Object, nil] the raw cell value
        # @return [String, nil] the cell's text, or nil for an empty cell
        def self.cell_text(value)
          case value
          when nil then nil
          when Date then value.iso8601
          else
            SanctionedEntity.exact_integer_text(value) || value.to_s.strip
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

        # Collapse a row Turkey published twice, verbatim, into one
        # record.
        #
        # A repeated row carrying identical content is one designee
        # entered twice, not two designees: keeping one copy loses
        # nothing. That is already the writer's verdict when two records
        # claim one filename, and the two layers have to reach it in the
        # same order. The gates below refuse any two records that share
        # an identifier, and a verbatim duplicate shares one — so
        # without this step a duplicated row would fail the whole source
        # here, and the tolerance the writer documents could never be
        # reached through a real parse.
        #
        # Identity is the record as it would be published: two rows
        # collapse when they serialize to the same YAML. That is the
        # writer's test too, which is what keeps the two layers from
        # disagreeing. It does mean a field left nil in one row and
        # empty in the other counts as one row — both publish the same
        # bytes, so collapsing them costs the corpus nothing.
        #
        # Two rows differing in any published value are two records, and
        # the gates below decide them on their merits.
        #
        # @param entities [Array<SanctionedEntity>] one per sheet row
        # @return [Array<SanctionedEntity>] one per distinct published
        #   record, in sheet order, keeping the first of each
        def self.collapse_duplicate_rows(entities)
          entities.uniq(&:to_yaml)
        end

        # Check every reserved reference still denotes the designee its
        # published IRI was minted for.
        #
        # Five outcomes, and only two of them are quiet. The holder is
        # identified by name, so the check is independent of row order,
        # and it runs whether or not the reference is duplicated.
        #
        # A claimant is decided on the SEGMENT the row's reference mints,
        # which is the address SanctionedEntity#local_id would put it at.
        # Comparing text instead would make this gate and identity
        # disagree, in both directions. A workbook spelling the reserved
        # number "187.0" still hands entity/tr/187 to its reserved holder,
        # and a gate reading raw text would see no claimant there and fail
        # a harvest that is in fact correct. In the other direction a row
        # reading "-187" never spells the reserved number, so a
        # text-reading gate would not count it as a claimant at all — yet
        # it lands on entity/tr/187 all the same, and with the reserved
        # holder delisted it would have taken that published address in
        # silence.
        #
        # @param entities [Array<SanctionedEntity>]
        # @raise [IntegrityError] when the reservation no longer resolves
        def self.verify_reservations!(entities)
          SanctionedEntity::RESERVED_LOCAL_IDS.each do |reference, holder|
            slug = holder[:slug]
            holders = entities.select do |entity|
              Utils::IriSanitizer.sanitize(entity.name.to_s) == slug
            end
            claimants = entities.select do |entity|
              SanctionedEntity.reference_segment(
                entity.reference_number
              ) == reference
            end

            check_reservation!(reference, holder, holders, claimants)
          end
        end

        # @raise [IntegrityError] unless the reservation resolves cleanly
        def self.check_reservation!(reference, holder, holders, claimants)
          slug = holder[:slug]

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

          verify_holder_identity!(reference, holder, holders.first)

          return if claimants.any? { |claimant| claimant.equal?(holders.first) }

          raise IntegrityError, reservation_error(
            reference, "the reserved name #{slug.inspect} now carries " \
                       "reference #{holders.first.reference_number.inspect}"
          )
        end

        # Refuse a row that matches the reserved slug but is not the
        # designee the slug stands for.
        #
        # The slug is lossy: it strips every non-ASCII letter and cuts at
        # 64 characters, so a different organisation can sanitize onto it.
        # Selecting the holder by slug is right — that is what the IRI is
        # minted from — but accepting it on the slug alone would hand a
        # published IRI to a lookalike without a word. Confirming the
        # full-fidelity name closes that, and does it the way every other
        # outcome here does: by stopping and naming what it found.
        #
        # @param reference [String] the reserved reference
        # @param holder [Hash] the reservation's slug and name
        # @param entity [SanctionedEntity] the row matching the slug
        # @raise [IntegrityError] when the row is a different designee
        def self.verify_holder_identity!(reference, holder, entity)
          actual = SanctionedEntity.strict_name(entity.name)
          return if actual == holder[:name]

          raise IntegrityError, reservation_error(
            reference, 'the row matching the reserved name is ' \
                       "#{actual.inspect}, not #{holder[:name].inspect} " \
                       '— two different designees share one sanitized name'
          )
        end

        # @return [String] reservation failure message
        def self.reservation_error(reference, detail)
          "tr: reserved reference #{reference.inspect} no longer resolves " \
            "— #{detail}. entity/tr/#{reference} is published; refusing to " \
            'republish it for a different designee. A human must decide ' \
            'which record keeps it.'
        end

        # Refuse a record that mints no IRI at all.
        #
        # Every record on this sheet is meant to become a graph node, and
        # SanctionedEntity#local_id is where each one is given something
        # to mint from. When it comes back with nothing, the IRI layer
        # refuses the record rather than emit a shared ".../unknown", so
        # the record cannot become a node at all. Fetch would still write
        # it to disk and report the source succeeded, and only harmonize
        # would discover it. The filename it lands under is either
        # obviously degenerate (tr----.yaml, from a reference of
        # punctuation) or not obviously anything: a row named "42" whose
        # id this parser refused is still written to tr-42.yaml, which
        # reads exactly like the record Turkey numbered 42.
        #
        # Caught here instead, where the whole workbook is in hand and
        # nothing has been written yet: the source fails, names the
        # record, and leaves the previous corpus in place.
        #
        # Three ways a record ends up with nothing to mint, and all three
        # are caught here: a published reference sanitizes away; a
        # reservation sends a numbered record to its name and the name
        # cannot serve as an id either; or Turkey published no reference
        # and that same name fallback fails. +fallback_name+ refuses a
        # blank name, a name carrying no ASCII alphanumeric, and a name
        # that slugs to a bare integer — the last because that is Turkey's
        # own numbering namespace. All three are this parser's own doing,
        # so leaving them to be discovered downstream would be the worse
        # failure.
        #
        # The unnumbered case belongs here as much as the numbered one. It
        # did not while a blank reference meant no identity attempt at
        # all; it does now that a blank reference falls back to the name,
        # because a record that tried to identify itself and failed is
        # exactly what this gate exists to stop reaching disk.
        #
        # This is not a rule about what a well-formed reference looks
        # like — it defers entirely to what Utils::IriSanitizer already
        # accepts.
        #
        # @param entities [Array<SanctionedEntity>]
        # @raise [IntegrityError] when a record mints nothing
        def self.verify_mintable_local_ids!(entities)
          unusable = entities.reject { |entity| mintable_id(entity.local_id) }
          return if unusable.empty?

          # Not "carries an identifier that mints no IRI": an unnumbered
          # record whose name cannot serve as an id carries no identifier
          # at all, and the gate now covers that case too.
          raise IntegrityError,
                'tr: record mints no IRI — ' \
                "#{describe_unmintable(unusable)}"
        end

        # Name the row by what it claimed, not by +local_id+, which never
        # carries a mintable identifier for a record reported here. It is
        # nil where the name fallback found nothing to offer, and where a
        # published reference sanitizes away it is that reference text —
        # "--", "١٢٣" — which the record does hold, but which sanitization
        # has just shown mints no IRI. Neither form tells an operator
        # anything the reference and the name do not tell them better.
        #
        # A numbered row is named by its reference: that is the claim this
        # parse could not honour. An unnumbered row has no reference to
        # quote, so it is named as unnumbered rather than as reference "".
        # Either way the designee's name follows, because that is what an
        # operator searches the workbook for.
        #
        # @param entities [Array<SanctionedEntity>] offending records
        # @return [String] human-readable report
        def self.describe_unmintable(entities)
          entities.map do |entity|
            reference = entity.reference_number.to_s.strip
            claim = if reference.empty?
                      'no reference'
                    else
                      "reference #{reference.inspect}"
                    end

            "#{claim} (#{entity.name.to_s.inspect})"
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
        # The name this gate knows it by; SanctionedEntity.minted_segment
        # is the definition, shared so that the reservation and this gate
        # cannot end up reading an address two different ways.
        #
        # @param local_id [Object, nil] the record's local id
        # @return [String, nil] the identifier it mints, or nil for none
        def self.mintable_id(local_id)
          SanctionedEntity.minted_segment(local_id)
        end

        # @return [String] human-readable collision report
        def self.describe_collisions(collisions)
          collisions.map do |id, rows|
            names = rows.map { |row| row.name.to_s.inspect }.join(', ')
            "#{id.inspect} <- #{names}"
          end.join('; ')
        end

        # Detect entity type from row data.
        #
        # Best effort, not ground truth. In the live workbook the
        # "Gerçek Kişi" column carries EVERY designee's name,
        # organisations included, and the "Tüzel Kuruluş/Organizasyon"
        # column is a type marker (the literal text "Tüzel
        # Kişi/Kuruluş/Organizasyon") rather than a name — filled on
        # some organisation rows and left blank on others. A row whose
        # marker Turkey omitted is indistinguishable here from a person
        # row: no other column separates them (many real persons carry
        # no birth data either), so such a row classifies "person"
        # however organisation-shaped its name reads.
        def self.detect_entity_type(row)
          # Marker column filled: Turkey typed the row as an organisation
          if row[:organization_name] && !row[:organization_name].empty?
            'organization'
          # A name with no marker: presumed person (see above)
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
