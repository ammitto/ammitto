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

        # The form Turkey publishes "Sıra No" in — an ASCII decimal number,
        # which all 239 numbers on the current sheet are.
        #
        # Nothing looser is accepted, because sanitization rewrites what it
        # is given and a rewritten value can land on top of another record:
        # "1.0", "-10", "10-" and "--10--" all sanitize to "10", the IRI of
        # whoever Turkey numbered 10, while "12/A" and "12A" sanitize to the
        # same "12a" as each other. A looser rule would have to reason about
        # which rewrites happen to be safe.
        DECIMAL_REFERENCE = /\A[0-9]+\z/
        private_constant :DECIMAL_REFERENCE

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
        # name their files. +reference_number+ itself is deliberately left
        # untouched, so harmonized output keeps reporting truthfully that
        # Turkey published no number for these designees.
        #
        # A cell that holds anything else is a third case, and it
        # deliberately does NOT fall back to the name: two such records that
        # happened to share a name would silently merge into one graph node.
        # "Absent" therefore means literally empty — nil, or blank after
        # stripping — and nothing more. A cell holding "--" or "١٢٣" is
        # present and unusable, not absent. Refusing returns nil, which the
        # IRI layer turns into a loud failure once ingestion stops
        # tolerating a missing local id.
        #
        # The IRI layer sanitizes whatever this returns, so the raw value is
        # returned here rather than a pre-slugged one.
        #
        # @return [String, nil] the local id, or nil when the record carries
        #   no identifier that can be trusted
        def local_id
          return nil if malformed?(reference_number)

          reference = reference_number.to_s.strip
          return fallback_name if reference.empty?
          return reference if reference.match?(DECIMAL_REFERENCE)

          nil
        end

        private

        # The record name, used when Turkey published no number.
        #
        # Refused when it would sanitize to a bare integer, because bare
        # integers are Turkey's own numbering namespace. This makes it
        # structurally impossible for a name-derived id to occupy a slot
        # Turkey assigned to a different designee.
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
        # Two shapes qualify. A container that survived assignment as a
        # container: the model layer stringifies most of them, but a list
        # stays a list, and +["1"].to_s+ sanitizes down to +1+. And a value
        # the model stringified into Ruby's inspection fallback,
        # +#<Enumerator:0x00007f...>+, which carries an object address and
        # would mint a different IRI on every process.
        #
        # Neither is evidence that Turkey omitted a cell — they are evidence
        # that the record is corrupt — so they are never allowed to reach
        # the name fallback. String is not Enumerable, so nothing legitimate
        # is caught.
        #
        # @param value [Object, nil] candidate identifier
        # @return [Boolean]
        def malformed?(value)
          value.is_a?(Enumerable) || value.to_s.strip.start_with?('#<')
        end

        # The value's text, if an IRI segment can be built from it.
        #
        # A value survives IRI sanitization only if it holds at least one
        # ASCII alphanumeric character, so blank, whitespace-only,
        # punctuation-only and non-Latin-only values return nil. This is a
        # question about the NAME — whether there is anything to slug — and
        # not about whether Turkey filled a cell in, which +local_id+
        # decides by emptiness alone.
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
              val = values[idx]
              row[header] = val.is_a?(Date) ? val.iso8601 : val&.to_s&.strip
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
