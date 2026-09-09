# frozen_string_literal: true

require 'lutaml/model'
require_relative '../../utils/iri_sanitizer'

module Ammitto
  module Sources
    module Tr
      # The four Turkish lists, which law each falls under and which one
      # the extractor actually handles are in lib/ammitto/sources/tr.rb.
      # Sanctioned entity from Turkey List D
      class SanctionedEntity < Lutaml::Model::Serializable
        attribute :name, :string
        # "person" or "organization" — the words this gem's own parser
        # writes. The comment here used to name a different pair,
        # "Individual, Entity", which nothing has ever produced; the
        # predicates below were written against that comment rather than
        # against .detect_entity_type, and so answered false for every
        # record ever parsed.
        attribute :entity_type, :string
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

        # Ruby's own scientific rendering of a Float, which is the other
        # shape a Float reaches a record file in: Float#to_s switches to
        # it at 1e15, so 999999999999999.0 was written "999999999999999.0"
        # while 1000000000000000.0 was written "1.0e+15".
        #
        # Deliberately matched to Ruby's exact output — a normalized
        # mantissa of 1 to 9, a dot, digits, a lowercase e, a SIGNED
        # exponent — and not to scientific notation in general. This
        # recognises a rendering an earlier fetch produced. A looser
        # pattern would also catch an identifier Turkey wrote, rewriting a
        # published reference of "1E5" into "100000", which is the
        # invention this layer refuses everywhere else. The leading digit
        # excludes 0 for the same reason: Ruby normalizes the mantissa and
        # never emits "0.5e+3", so that spelling is somebody's own text.
        SCIENTIFIC_FLOAT = /\A-?[1-9]\.\d+e[+-]\d+\z/

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
          text = value.to_s.strip
          match = WHOLE_DECIMAL.match(text)
          return match[1] if match

          scientific_integer_text(text)
        end

        # The digits of a whole number an earlier fetch wrote in Ruby's
        # scientific rendering.
        #
        # Float#to_s changes shape at 1e15, so the record road meets the
        # same artefact in two spellings: "1000.0" below the threshold and
        # "1.0e+15" above it. Recognising only the first would leave the
        # two roads disagreeing exactly where MAX_SAFE_INTEGER still says
        # the value is exact — a re-fetched sheet minting
        # entity/tr/1000000000000000 while the record file it replaces
        # minted entity/tr/10e15, which is the split this pair of methods
        # exists to prevent.
        #
        # The expansion is delegated to +exact_integer_text+ rather than
        # restated, so the sheet's rule and this one cannot drift: the same
        # method decides exactness and the same MAX_SAFE_INTEGER bound
        # applies. Past that bound neither road rewrites anything, so they
        # already agree and this returns nil.
        #
        # Which spelling counts is decided by ROUND TRIP, not by the
        # pattern: the text must be exactly what Ruby would print for the
        # value it parses to. The pattern is only a cheap pre-filter, and
        # a pattern is the wrong instrument for this question — it can
        # describe Ruby's format but never BE it, and every spelling it
        # admits by mistake is a published reference silently rewritten.
        # "1.00e+15" and "1.0e+015" both name the same number and both
        # look like renderings; neither is one, so neither is touched.
        #
        # @param text [String] the stripped reference text
        # @return [String, nil] the digits, or nil when the text is not
        #   Ruby's own rendering of a provably whole number
        def self.scientific_integer_text(text)
          return nil unless SCIENTIFIC_FLOAT.match?(text)

          float = Float(text)
          return nil unless float.to_s == text

          exact_integer_text(float)
        rescue ArgumentError
          nil
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

        # Whether this record carries the parser's "person"
        # classification.
        #
        # The word compared is the one .detect_entity_type emits — that
        # method writes "person" or "organization" and nothing else, and
        # fetch saves the word verbatim. That bounds the parser, not the
        # record: harmonize re-reads record files, and the YAML mapping
        # admits whatever string a file carries. The pair of predicates
        # stays total over that open set because this one matches the
        # single word meaning person and #organization? takes the
        # complement, mirroring Transformer#map_entity_type. Comparing
        # against "individual" instead made this false for every record,
        # and #organization? false with it, leaving no value of
        # entity_type for which either predicate answered true.
        #
        # A true answer repeats the classification; it does not vouch
        # for the designee. The classifier's only organisation signal is
        # a marker column Turkey fills on some organisation rows and
        # leaves blank on others, so part of List D's organisations —
        # DEFENCE INDUSTRIES ORGANISATION (DIO) among them — carry
        # "person" and answer true here.
        #
        # @return [Boolean]
        def person?
          entity_type.to_s.downcase == 'person'
        end

        # Whether this record carries anything but the "person"
        # classification.
        #
        # The complement rather than an equality test, so that it agrees
        # with Transformer#map_entity_type for every value rather than
        # only for the two the parser writes. That method sends "person"
        # down the person branch and everything else — a blank
        # entity_type, the "entity" spelling, a word from some future
        # column — down the organization branch, and builds an
        # OrganizationEntity accordingly. An `== "organization"` test
        # would answer false about records the gem does harmonize as
        # organizations, which is the same defect in a quieter form.
        #
        # @return [Boolean]
        def organization?
          !person?
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
        # The reservation is looked up by the SEGMENT the reference mints,
        # not by its text, because what the reservation protects is an
        # address and the segment is the address. Text comparison misses
        # every spelling sanitization erases on the way there: a workbook
        # reformatted so 187 arrives as "187.0" must still hand
        # entity/tr/187 to the same designee, and so must a row reading
        # "-187", "187-" or "18.7", none of which spell 187 but all of
        # which land on it.
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
          holder = RESERVED_LOCAL_IDS[self.class.minted_segment(id)]
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

        # The IRI segment a value would actually mint, or nil for none.
        #
        # The last transform between an identifier and the graph: the IRI
        # layer sanitizes whatever it is handed, and THAT is the address a
        # record ends up at. Anything deciding which record owns which
        # address has to ask this rather than compare identifier text,
        # because sanitization is lossy — "-187", "187-" and "18.7" all
        # arrive at 187 without ever spelling it.
        #
        # @param value [Object, nil] an identifier
        # @return [String, nil] the segment it mints, or nil for none
        def self.minted_segment(value)
          return nil if value.nil?

          Utils::IriSanitizer.sanitize_local_id!(value, source: 'tr',
                                                        kind: 'entity')
        rescue Utils::IriSanitizer::MissingLocalIdError
          nil
        end

        # The segment a row's published reference would mint.
        #
        # Both steps, in the order identity applies them: the redundant
        # spelling is reduced first, then the result is sanitized. This is
        # the question a reservation asks of a row — "would this reference
        # land on the address I protect?" — and it is asked of the
        # reference rather than of +local_id+, because a row the
        # reservation has already sent to its name no longer mints from
        # its reference at all.
        #
        # @param value [Object, nil] a raw reference
        # @return [String, nil] the segment it mints, or nil for none
        def self.reference_segment(value)
          minted_segment(canonical_reference(value))
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
    end
  end
end
