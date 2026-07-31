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

        # A number spelled with a redundant zero fraction, as Roo's Float
        # renders it and as such a value is then written to YAML.
        WHOLE_DECIMAL = /\A(-?\d+)\.0+\z/

        # Largest integer a Float still attributes to one workbook value.
        # 2**53 is itself excluded even though it is exactly
        # representable: nothing between it and 2**53 + 2 is, so
        # 9007199254740993 rounds onto 9007199254740992.0 and the Float
        # stops saying which integer the cell held. Converting past this
        # point would assert a precision the value does not carry.
        MAX_SAFE_INTEGER = (2**53) - 1

        # Why a whole number needs one spelling at all.
        #
        # Roo picks Integer or Float for a numeric cell from the cell's
        # DISPLAY FORMAT rather than from the value
        # (Excelx::Cell::Number#create_numeric returns a Float whenever the
        # format string contains ".0"). So Turkey's row 1 arrives as 1 or
        # as 1.0 purely by how the workbook was formatted — and "1.0"
        # sanitizes to "10", the IRI of whoever Turkey numbered 10. A
        # cosmetic reformat would silently renumber every designee on the
        # sheet, and a sheet carrying both formats would merge two of them.
        #
        # Reducing the artefact undoes a rendering; it does not reinterpret
        # a value, because 1.0 and 1 ARE the same number and Turkey
        # published one cell, not two.
        #
        # A reference reaches identity by TWO roads, and each needs a
        # different rule, which is why these are two methods rather than
        # one. At the sheet the artefact is a Float, and only a Float —
        # a text cell there is workbook text and must survive verbatim.
        # In a record file the sheet is long gone and the artefact has
        # become the string "1.0", so that is what has to be recognised.

        # A Float's integer text, when the Float is provably that integer.
        #
        # The sheet road. Restricted to Float on purpose: a literal text
        # cell reading "01.0" or "1.00" is an identifier Turkey wrote, not
        # a rendering of a number, and rewriting it would corrupt passport,
        # registration and gazette values that main preserved exactly.
        #
        # +finite?+ first, because NaN and Infinity equal no integer and
        # Float::INFINITY#to_i raises.
        #
        # @param value [Object, nil] a raw cell value
        # @return [String, nil] the integer's digits, or nil when the value
        #   is not a Float that provably holds one
        def self.exact_integer_text(value)
          return nil unless value.is_a?(Float)
          return nil unless value.finite?
          return nil unless value.abs <= MAX_SAFE_INTEGER
          return nil unless value == value.to_i

          value.to_i.to_s
        end

        # The digits of a number written with a redundant zero fraction.
        #
        # The record-file road, for a value an earlier fetch wrote before
        # the sheet reader canonicalized it. No precision limit applies:
        # these digits are the workbook's own text, not a Float's
        # approximation of them.
        #
        # A real fractional part is not matched and gets nil — 1.5 is not
        # the same number as 1 or as 15, so rewriting it would invent data.
        #
        # The captured digits are returned verbatim rather than passed
        # through Integer, so exactly the redundant fraction is removed and
        # nothing else. Reading them as a number would also strip leading
        # zeros, which would split one designee two ways: "01" would keep
        # entity/tr/01 while "01.0" moved to entity/tr/1, on a difference
        # this method exists to erase.
        #
        # @param value [Object, nil] a record's reference text
        # @return [String, nil] the digits, or nil when the text does not
        #   spell a whole number redundantly
        def self.whole_decimal_text(value)
          match = WHOLE_DECIMAL.match(value.to_s.strip)

          match && match[1]
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
        # Each entry carries the designee's name twice, because the two
        # forms answer different questions. +slug+ is what the IRI is
        # minted from, so it is what decides whether a row may keep the
        # reference. +name+ is the same name at full fidelity, and exists
        # only to confirm that the row matching that slug really is the
        # designee: sanitizing strips every non-ASCII letter and truncates
        # at 64 characters, so two different organisations whose names
        # differ only in what it strips share one slug. Without the second
        # form, such a lookalike would be accepted as the holder and take
        # a published IRI silently.
        RESERVED_LOCAL_IDS = {
          '187' => {
            slug: 'defense-technology-and-science-research-enter-dtsrc',
            name: 'defense technology and science research çenter (dtsrc)'
          }.freeze
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
        # Normally Turkey's own "Sıra No", which the parser stores as
        # +reference_number+. Two things stop that number from being the
        # answer on its own, and this method resolves both.
        #
        # BLANK CELLS. The block of Iranian designees appended to List D
        # leaves the column empty, so a sizeable minority of rows carry
        # no upstream number at all. Those rows fall back to the entity
        # name — the only stable field they carry — which is the same
        # surrogate the fetcher has always fallen back to when the
        # reference was absent. Aligning the two layers is the whole
        # point: tr-abbas-rashidi.yaml has sat beside tr-99.yaml since the
        # fetcher was written, while the transformer had no answer for
        # those rows at all — first collapsing all 37 onto one shared
        # ".../unknown" node, and, since the IRI layer stopped tolerating
        # a blank local id, failing the whole source. The two layers now
        # share this method outright: Cmd::FetchCommand#filename_for_item
        # reads +local_id || name+, so a record that gets its own file
        # also gets its own graph node.
        #
        # RESERVED NUMBERS. Turkey assigns "Sıra No" 187 to two different
        # organisations, so a number can also identify more than one
        # record. Where the number is reserved for a different designee
        # (see RESERVED_LOCAL_IDS), the record falls back to its name too,
        # so both designees survive as distinct records rather than the
        # later one overwriting the earlier.
        #
        # A published reference is otherwise taken as published, whatever
        # its shape: stripped of surrounding whitespace, which the
        # sanitizer collapses away regardless, reduced by +canonical+ to
        # one spelling of a whole number, and otherwise untouched. The two
        # shapes +malformed?+ names are the only exceptions, and they are
        # not references. No rule here decides what a well-formed "Sıra
        # No" looks like, because the shape is not Turkey's to promise.
        # The numbers arrive through Roo, whose
        # Excelx::Cell::Number#create_numeric picks Integer or Float from
        # the cell's DISPLAY FORMAT — a format string containing ".0"
        # yields a Float — so the same 239 numbers reach this method as
        # "1" or as "1.0" depending on how the workbook was formatted. A
        # bare-decimal gate turned that cosmetic difference into the loss
        # of every numbered record on the sheet.
        #
        # The reservation is looked up by the CANONICAL reference, not the
        # raw text, because the reservation protects a published IRI and
        # the canonical form is what mints it: a workbook reformatted so
        # 187 arrives as "187.0" must still hand entity/tr/187 to the same
        # designee.
        #
        # The name fallback is reserved for those two cases — a cell
        # Turkey genuinely left empty (nil, or blank after stripping), and
        # a reference reserved for someone else. It is deliberately NOT a
        # catch-all for a reference that turns out to be unusable: two such
        # records that happened to share a name would silently merge into
        # one graph node. A reference that survives sanitization as nothing
        # ("--", "١٢٣") therefore mints no id at all, and the IRI layer
        # raises Utils::IriSanitizer::MissingLocalIdError rather than emit
        # a shared ".../unknown".
        #
        # The IRI layer sanitizes whatever this returns, so the value is
        # returned as text rather than pre-slugged here.
        #
        # @return [String, nil] the local id, or nil when the record carries
        #   no identifier that can be trusted
        def local_id
          return nil if malformed?(reference_number)

          reference = reference_number.to_s.strip
          return fallback_name if reference.empty?

          id = canonical(reference)
          holder = RESERVED_LOCAL_IDS[id]
          return id if holder.nil? || sanitized_name == holder[:slug]

          fallback_name
        end

        # The name at the fidelity the IRI slug throws away.
        #
        # Case and run-of-whitespace differences are absorbed, because
        # Turkey's cells carry stray spacing that says nothing about which
        # designee a row is. Everything the slug drops — the non-ASCII
        # letters, the punctuation, anything past 64 characters — is kept,
        # because that is the whole reason this form exists.
        #
        # @param value [Object] a designee name
        # @return [String] comparable name
        def self.strict_name(value)
          value.to_s.unicode_normalize(:nfkc).gsub(/\s+/, ' ').strip.downcase
        end

        # The reference as identity should read it.
        #
        # Applied here as well as at the sheet because harmonize does not
        # go through the sheet: it re-reads a record file written by an
        # earlier fetch, so a file committed before the sheet was
        # normalized still carries "1.0" and would otherwise mint
        # entity/tr/10 — reference 10's IRI. Making both roads agree is
        # what keeps one designee on one node across that changeover.
        #
        # +reference_number+ itself is deliberately untouched, so the
        # harmonized output keeps reporting the text the record actually
        # holds rather than a value this layer invented.
        #
        # Public because the corpus gates have to read a reference the
        # same way identity does: SanctionsList.verify_reservations!
        # decides which row claims a reserved number, and a raw-text
        # comparison there would disagree with +local_id+ the moment a
        # workbook spells that number "187.0".
        #
        # @param value [Object, nil] a reference, raw or stripped
        # @return [String] the reference, or its canonical whole number
        def self.canonical_reference(value)
          reference = value.to_s.strip

          whole_decimal_text(reference) || reference
        end

        private

        # @see .canonical_reference
        # @param reference [String] the stripped reference text
        # @return [String] the reference, or its canonical whole number
        def canonical(reference)
          self.class.canonical_reference(reference)
        end

        # The record name, used when the record cannot take its own
        # number — because Turkey published none, or because the number
        # it published is reserved for a different designee.
        #
        # Refused when it would sanitize to a bare integer, because bare
        # integers are Turkey's own numbering namespace. This makes it
        # structurally impossible for a name-derived id to occupy a slot
        # Turkey assigned to a different designee. Tested against the
        # sanitized form, not the raw one, so it holds however that slug
        # space is reached: a reference arriving as "1.0" or "-10" also
        # slugs to a bare integer, and a name slugging to the same integer
        # is still refused.
        #
        # Claim it exactly: this keeps a name out of the BARE-INTEGER slug
        # space and nothing more. It does not make a name-derived id unique
        # in general — two names can slug alike, and a name can slug onto a
        # non-integer reference — because uniqueness is a corpus-level
        # question and one record cannot see another. The list layer is
        # where that belongs, in
        # SanctionsList.verify_distinct_local_ids!.
        #
        # @return [String, nil]
        def fallback_name
          return nil if malformed?(name)

          str = scalar_text(name)
          return nil if str.nil?
          return nil if sanitized_name.match?(/\A\d+\z/)

          str
        end

        # Whether a value is structurally corrupt rather than merely odd.
        #
        # This is not the format gate +local_id+ refuses to have. Odd
        # references — "1.0", "12/A", "E.47.A.3" — are accepted; these two
        # shapes are not references at all, and each breaks something a
        # reference has to do.
        #
        # A container that survived assignment as a container: the model
        # layer stringifies most of them, but a list stays a list, and
        # +["1"].to_s+ sanitizes down to +1+, so the record would silently
        # take whatever IRI Turkey numbered 1. And a value the model
        # stringified into Ruby's inspection fallback,
        # +#<Enumerator:0x00007f...>+, which carries an object address and
        # would therefore mint a different IRI on every process — the one
        # thing an identifier may never do, and the reason this method
        # applies to the reference slot and not only the name.
        #
        # Neither is evidence that Turkey omitted a cell — they are evidence
        # that the record is corrupt — so neither falls back to the name
        # either. String is not Enumerable, so nothing legitimate is caught.
        #
        # The +#<+ test is a narrow heuristic, not a proof of determinism:
        # it catches Ruby's default inspection form, which is the shape an
        # address actually reaches this model in, and misses an address
        # nested inside some other string. It errs the safe way — a false
        # positive refuses the record loudly rather than minting a wrong
        # IRI. Proving a value is a plain scalar belongs at the
        # deserialization boundary, for every source at once.
        #
        # @param value [Object, nil] candidate identifier
        # @return [Boolean]
        def malformed?(value)
          value.is_a?(Enumerable) || value.to_s.strip.start_with?('#<')
        end

        # The value's text, if a name can be slugged from it.
        #
        # Requires one ASCII alphanumeric character, so blank,
        # whitespace-only, punctuation-only and non-Latin-only names return
        # nil. Deliberately STRICTER than the IRI layer, which also keeps
        # underscores and would happily mint entity/tr/_ from a name of
        # "_": a surrogate carrying no letter or digit identifies nobody,
        # and this is the layer that invents surrogates. Refusing here
        # turns it into the same loud failure a blank name gets.
        #
        # This is a question about the NAME — whether there is anything to
        # slug — and not about whether Turkey filled a cell in, which
        # +local_id+ decides by emptiness alone.
        #
        # @param value [Object, nil] candidate identifier
        # @return [String, nil] the stripped text, or nil if it carries none
        def scalar_text(value)
          str = value.to_s.strip
          str.match?(/[a-zA-Z0-9]/) ? str : nil
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
        # A claimant is decided on the CANONICAL reference, which is what
        # SanctionedEntity#local_id mints from. Comparing the raw text
        # instead would make this gate and identity disagree: a workbook
        # spelling the reserved number "187.0" still hands entity/tr/187
        # to its reserved holder, and a gate reading raw text would see no
        # claimant there and fail a harvest that is in fact correct.
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
              SanctionedEntity.canonical_reference(
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
