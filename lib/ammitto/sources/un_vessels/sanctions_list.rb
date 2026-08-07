# frozen_string_literal: true

require 'lutaml/model'
require_relative 'vessel'

module Ammitto
  module Sources
    module UnVessels
      # SanctionsList represents the UN Security Council Designated Vessels List
      #
      # The 1718 Committee publishes this list only as a PDF; from_pdf
      # extracts the document text and from_text parses the vessel table
      # out of it.
      #
      class SanctionsList < Lutaml::Model::Serializable
        # Raised when the extracted PDF text fails the structural
        # checks in from_text. The committee reformats this PDF rather
        # than versioning it, and VESSEL_ROW is anchored to the current
        # layout — a layout change makes the regexp go quiet rather
        # than wrong, so it must fail the harvest loudly instead of
        # yielding a green empty list.
        class IntegrityError < StandardError; end

        attribute :vessels, Vessel, collection: true
        attribute :fetched_at, :string
        attribute :source, :string

        # One vessel row of the list's table, as PDF::Reader lays the
        # text out: the numbered-name cell ("1: NAME 2: FORMER NAME…"),
        # the IMO cell (a 7-digit number, or the literal "Does not
        # exist" — one designated vessel has no IMO number), and the
        # date-of-designation cell (d-Mon-yy, or "na"). Continuation
        # lines that also begin with "1:" but hold an MMSI list do not
        # match: an MMSI has nine digits, not seven, and no date follows.
        VESSEL_ROW = /
          ^\s*1:\s+
          (?<names>\S.*?)\s{2,}
          (?<imo>\d{7}|Does\snot\sexist)\s+
          (?<date>\d{1,2}-[A-Za-z]{3}-\d{2}|na)\b
        /x

        # Names inside the numbered-name cell are separated by " N: ".
        NAME_SEPARATOR = /\s+\d+:\s+/

        # Every row of this PDF is a 1718 Committee (DPRK) designation:
        # the resolution is a property of the document, not of a row,
        # so it is stamped constant onto each minted vessel.
        # Transformer#create_regime keys the UN-1718 regime off it —
        # left nil, every vessel would fall back to the generic UN
        # regime.
        RESOLUTION = 'Resolution 1718 (2006)'

        # Create SanctionsList from manually converted data
        # @param data [Hash] structured data from PDF conversion
        # @return [SanctionsList]
        def self.from_converted_data(data)
          list = new
          list.source = 'un_vessels'
          list.fetched_at = Time.now.utc.iso8601
          list.vessels = (data['vessels'] || []).map do |vessel_data|
            Vessel.from_hash(vessel_data)
          end
          list
        end

        # Create SanctionsList from the published PDF
        # @param pdf_path [String] path to PDF file
        # @return [SanctionsList]
        def self.from_pdf(pdf_path)
          require 'pdf-reader'

          reader = PDF::Reader.new(pdf_path)
          from_text(reader.pages.map(&:text).join("\n"))
        end

        # Create SanctionsList from the PDF's extracted text
        # @param text [String] page text of the published PDF
        # @return [SanctionsList]
        # @raise [IntegrityError] when the parsed set fails a
        #   structural invariant (see the verify_* methods)
        def self.from_text(text)
          vessels = text.each_line.filter_map do |line|
            vessel_from_line(line)
          end

          verify_rows_present!(vessels)
          verify_distinct_ids!(vessels)
          verify_imo_presence!(vessels)

          new.tap do |list|
            list.source = 'un_vessels'
            list.fetched_at = Time.now.utc.iso8601
            list.vessels = vessels
          end
        end

        # A zero-row parse is a layout change, never an empty list —
        # the DPRK vessel designations have never been vacated.
        # @param vessels [Array<Vessel>]
        # @raise [IntegrityError] when no line matched VESSEL_ROW
        def self.verify_rows_present!(vessels)
          return unless vessels.empty?

          raise IntegrityError,
                'un_vessels: no vessel row matched the extracted PDF ' \
                'text — the document layout has changed'
        end

        # Two rows landing on one id means rows collapsed onto one
        # record: the later file overwrites the earlier one at save
        # time, silently dropping a designated vessel.
        # @param vessels [Array<Vessel>]
        # @raise [IntegrityError] when two rows share an id
        def self.verify_distinct_ids!(vessels)
          duplicates = vessels.map(&:id).tally.select { |_, n| n > 1 }
          return if duplicates.empty?

          raise IntegrityError,
                'un_vessels: rows collapse onto one id — ' \
                "#{duplicates.keys.join(', ')}"
        end

        # A set with no numeric IMO at all cannot be the vessels
        # table: every published revision has carried exactly one
        # IMO-less vessel, so an all-nil set means the IMO column
        # stopped parsing.
        # @param vessels [Array<Vessel>]
        # @raise [IntegrityError] when no row carries an IMO number
        def self.verify_imo_presence!(vessels)
          return if vessels.any?(&:imo_number)

          raise IntegrityError,
                'un_vessels: no parsed row carries an IMO number — ' \
                'the IMO column no longer parses'
        end

        # Parse one text line into a Vessel, or nil for a non-row line
        # @param line [String] one line of extracted PDF text
        # @return [Vessel, nil]
        def self.vessel_from_line(line)
          match = VESSEL_ROW.match(line)
          return nil unless match

          Vessel.new.tap do |vessel|
            vessel.entity_type = 'vessel'
            vessel.names = name_variants(match[:names])
            vessel.imo_number = match[:imo] if /\A\d{7}\z/.match?(match[:imo])
            vessel.designation_date = Vessel.parse_date(match[:date])
            vessel.resolution = RESOLUTION
            vessel.id = "un-vessel-#{vessel.local_id}"
          end
        end

        # Split the numbered-name cell into variants, first name primary
        # @param cell [String] the name cell without its leading "1: "
        # @return [Array<NameVariant>]
        def self.name_variants(cell)
          cell.strip.split(NAME_SEPARATOR).each_with_index.map do |name, index|
            NameVariant.new(full_name: name.strip, is_primary: index.zero?)
          end
        end

        # Get all vessels
        # @return [Array<Vessel>]
        def all_vessels
          vessels
        end

        # Get count of vessels
        # @return [Integer]
        def count
          vessels.length
        end
      end
    end
  end
end
