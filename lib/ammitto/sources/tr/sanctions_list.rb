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
        # The IRI layer sanitizes whatever this returns, so the raw value is
        # returned here rather than a pre-slugged one.
        #
        # @return [String, nil] the local id, or nil when the record carries
        #   nothing an IRI segment can be built from
        def local_id
          trusted_reference || fallback_name
        end

        private

        # The upstream number, but only when sanitization will not rewrite
        # it into a different token.
        #
        # Sanitization deletes characters it does not recognize, and a
        # deletion can merge digits: a spreadsheet cell holding the float
        # 1.0 stringifies to "1.0" and sanitizes to "10", which is the IRI
        # of whichever record Turkey numbered 10. So a reference number is
        # trusted only when it is built entirely from characters the
        # sanitizer keeps or converts — alphanumerics, hyphen, underscore
        # and whitespace. All 239 numbers Turkey currently publishes are
        # plain digits and pass through untouched; anything stranger falls
        # through to the name rather than quietly claiming someone's number.
        #
        # @return [String, nil]
        def trusted_reference
          str = identifiable(reference_number)
          return nil unless str&.match?(/\A[a-zA-Z0-9\-_\s]+\z/)

          str
        end

        # The record name, used when Turkey published no number.
        #
        # Refused when it would sanitize to a bare integer, because bare
        # integers are Turkey's own numbering namespace. This makes it
        # structurally impossible for a name-derived id to occupy a slot
        # Turkey assigned to a different designee.
        #
        # @return [String, nil]
        def fallback_name
          str = identifiable(name)
          return nil if str.nil?
          return nil if Utils::IriSanitizer.sanitize(str).match?(/\A\d+\z/)

          str
        end

        # Whether a value can serve as an IRI segment.
        #
        # A value survives IRI sanitization only if it holds at least one
        # ASCII alphanumeric character. Blank, whitespace-only,
        # punctuation-only and non-Latin-only values are rejected so that
        # callers stay loud about a genuinely unidentifiable record instead
        # of collapsing several of them onto one placeholder IRI.
        #
        # Containers are rejected outright. Hand-written YAML can put a list
        # or a mapping in a scalar slot, and +Array#to_s+ would then sanitize
        # down to its first element — so +reference_number: [1]+ would
        # quietly claim the IRI of the record numbered 1. String is not
        # Enumerable, so this rejects only real containers.
        #
        # @param value [Object, nil] candidate identifier
        # @return [String, nil] the stripped value, or nil if unusable
        def identifiable(value)
          return nil if value.is_a?(Enumerable)

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
