# frozen_string_literal: true

require 'lutaml/model'
require 'roo'
require_relative '../../utils/iri_sanitizer'

module Ammitto
  module Sources
    module Tr
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

        def person?
          entity_type&.downcase == 'individual'
        end

        def organization?
          entity_type&.downcase == 'entity'
        end

        # Local identifier this record's IRIs are minted from.
        #
        # Turkey numbers List D rows with a "Sıra No" column, which the
        # parser stores as +reference_number+. The block of Iranian
        # designees appended to that sheet leaves the column blank, so a
        # sizeable minority of rows carry no upstream number at all. Those
        # rows fall back to the entity name — the only stable field they
        # carry — which is the same surrogate the fetcher already uses to
        # name their files (see Cmd::FetchCommand#filename_for_item, where
        # tr has always read +reference_number || name+). Aligning the two
        # layers is the whole point: tr-abbas-rashidi.yaml has sat beside
        # tr-99.yaml since the fetcher was written, while the transformer
        # had no answer for those rows at all — first collapsing all 37
        # onto one shared ".../unknown" node, and, since the IRI layer
        # stopped tolerating a blank local id, failing the whole source.
        #
        # A published reference is taken as published, whatever its shape:
        # stripped of surrounding whitespace, which the sanitizer collapses
        # away regardless, and otherwise untouched. The two shapes
        # +malformed?+ names are the only exceptions, and they are not
        # references. No rule here decides what a well-formed "Sıra No"
        # looks like, because the shape is not Turkey's to promise. The
        # numbers arrive through Roo, whose Excelx::Cell::Number#create_numeric
        # picks Integer or Float from the cell's DISPLAY FORMAT — a format
        # string containing ".0" yields a Float — so the same 239 numbers
        # reach this method as "1" or as "1.0" depending on how the
        # workbook was formatted. A bare-decimal gate turned that cosmetic
        # difference into the loss of every numbered record on the sheet.
        #
        # The name fallback is reserved for a cell Turkey genuinely left
        # empty — nil, or blank after stripping. It is deliberately NOT a
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
          return canonical(reference) unless reference.empty?

          fallback_name
        end

        private

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
        # @param reference [String] the stripped reference text
        # @return [String] the reference, or its canonical whole number
        def canonical(reference)
          self.class.whole_decimal_text(reference) || reference
        end

        # The record name, used when Turkey published no number.
        #
        # Refused when it would sanitize to a bare integer, because bare
        # integers are where Turkey's own numbering lands. Tested against
        # the sanitized form, not the raw one, so it holds however that
        # slug space is reached: a reference arriving as "1.0" or "-10"
        # also slugs to a bare integer, and a name slugging to the same
        # integer is still refused.
        #
        # Claim it exactly: this keeps a name out of the BARE-INTEGER slug
        # space and nothing more. It does not make a name-derived id unique
        # in general — two names can slug alike, and a name can slug onto a
        # non-integer reference — because uniqueness is a corpus-level
        # question and one record cannot see another. The list layer is
        # where that belongs.
        #
        # @return [String, nil]
        def fallback_name
          return nil if malformed?(name)

          str = scalar_text(name)
          return nil if str.nil?
          return nil if Utils::IriSanitizer.sanitize(str).match?(/\A\d+\z/)

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
      end

      # Alias for backward compatibility with harmonize command
      Entity = SanctionedEntity

      # Collection of sanctioned entities from Turkey
      class SanctionsList < Lutaml::Model::Serializable
        attribute :entities, SanctionedEntity, collection: true

        yaml do
          map 'entities', to: :entities
        end

        # Parse from XLSX file
        # @param xlsx_path [String] path to XLSX file
        # @return [SanctionsList]
        def self.from_xlsx(xlsx_path)
          list = new(entities: [])

          xlsx = Roo::Excelx.new(xlsx_path)
          sheet = xlsx.sheet(0)

          # Get headers from first row
          headers = sheet.row(1).map { |h| normalize_header(h) }

          (2..sheet.last_row).each do |row_num|
            values = sheet.row(row_num)

            row = {}
            headers.each_with_index do |header, idx|
              row[header] = cell_text(values[idx])
            end

            # Determine name - could be in 'name' (individual) or 'organization_name' column
            name = row[:name] || row[:organization_name] || row[:former_name]
            next if name.nil? || name.empty?

            entity_type = detect_entity_type(row)

            entity = SanctionedEntity.new(
              name: name,
              entity_type: entity_type,
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
              address: row[:address]
            )

            list.entities << entity
          end

          list
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

        # Normalize header to symbol
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
          when /uyruk/ then :nationality
          when /listeye.*al.*nma/, /tarih/ then :listed_date
          when /di.*er.*bilgi/ then :remarks
          when /do.*um.*yer/ then :place_of_birth
          when /anne.*ad/ then :mother_name
          when /baba.*ad/ then :father_name
          when /do.*um.*tarih/ then :date_of_birth
          when /.*rg.*t/ then :organization
          when /gazete/ then :official_gazette
          when /bkk.*cbk/, /karar/ then :decision_number
          else
            # Generate symbol from cleaned header
            h.gsub(/\s+/, '_').to_sym
          end
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

        def count
          entities.size
        end
      end
    end
  end
end
