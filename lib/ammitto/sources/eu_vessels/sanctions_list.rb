# frozen_string_literal: true

require 'date'
require 'lutaml/model'
require_relative '../../errors/base_error'
require_relative 'vessel'
require_relative 'subject_to'

module Ammitto
  module Sources
    module EuVessels
      # SanctionsList represents the EU Designated Vessels list hosted by
      # the Danish Maritime Authority: vessels under Article 3s and Annex
      # XLII of Council Regulation (EU) 833/2014, and vessels under Council
      # Regulation (EU) 2017/1509 (DPRK).
      #
      # Source: https://www.dma.dk/growth-and-framework-conditions/maritime-sanctions/general-information/eu-vessel-designations
      #
      class SanctionsList < Lutaml::Model::Serializable
        attribute :vessels, Vessel, collection: true

        # Columns every row is read from, by their normalised header.
        COLUMNS = %w[vessel_name imo_number date_of_application subject_to].freeze

        # Parse XLSX file and create SanctionsList
        # @param file_path [String] path to XLSX file
        # @return [SanctionsList]
        # @raise [Ammitto::ParseError] on a missing column or a row that
        #   cannot be read as a designation
        def self.from_xlsx(file_path)
          require 'roo'

          xlsx = Roo::Spreadsheet.open(file_path)
          xlsx.default_sheet = xlsx.sheets.first
          keys = header_keys(xlsx.row(1))

          rows = (2..xlsx.last_row).filter_map do |row_num|
            row = xlsx.row(row_num)
            next if row.all? { |cell| blank?(cell) }

            Vessel.from_row_data(read_row(row, keys, row_num))
          end

          new(vessels: consolidate(rows))
        end

        # @param headers [Array] the header row
        # @return [Array<String, nil>] the normalised key of each column
        # @raise [Ammitto::ParseError] when a column this parser reads is
        #   missing, which would otherwise publish every row without it
        def self.header_keys(headers)
          keys = headers.map do |header|
            next if header.nil?

            header.to_s.downcase.strip.gsub(/[^a-z0-9]+/, '_').gsub(/^_|_$/, '')
          end
          missing = COLUMNS - keys
          return keys if missing.empty?

          raise Ammitto::ParseError, "eu_vessels: workbook header #{headers.inspect} lacks #{missing.join(', ')}"
        end

        # One row as a hash keyed by column, refused when it does not read
        # as a designation. DMA's CSV twin of this workbook has had rows
        # whose cells shifted a column, and a shifted row read by position
        # publishes a name as an IMO number or a date as a measure, so each
        # cell is checked for the kind of value its column holds.
        #
        # @param row [Array] the cells
        # @param keys [Array<String, nil>] column keys from `header_keys`
        # @param row_num [Integer] the sheet row, for the error
        # @return [Hash]
        # @raise [Ammitto::ParseError] naming the row and what is wrong
        def self.read_row(row, keys, row_num)
          problem = ->(why) { raise Ammitto::ParseError, "eu_vessels: row #{row_num} #{row.inspect} #{why}" }

          stray = row.each_index.select { |idx| keys[idx].nil? && !blank?(row[idx]) }
          problem.call("has cells outside the header's columns (#{stray.map { |i| i + 1 }.join(', ')})") if stray.any?

          data = keys.each_with_index.to_h { |key, idx| [key, row[idx]] }
          problem.call('has no vessel name') if blank?(data['vessel_name'])

          imo = data['imo_number']
          imo = imo.to_i if imo.is_a?(Float) && imo == imo.floor
          problem.call("has IMO number #{imo.inspect}, not seven digits") unless blank?(imo) || imo.to_s.strip.match?(/\A\d{7}\z/)
          data['imo_number'] = blank?(imo) ? nil : imo.to_s.strip

          data['date_of_application'] = read_date(data['date_of_application']) ||
                                        problem.call("has date of application #{data['date_of_application'].inspect}, not a date")
          SubjectTo.parse(data['subject_to'])
          data
        end

        # @param value [Object] a date cell
        # @return [Date, nil] nil when the cell does not hold a date
        def self.read_date(value)
          return value if value.is_a?(Date)
          return nil if blank?(value)

          Date.strptime(value.to_s.strip, '%Y-%m-%d')
        rescue ArgumentError
          nil
        end

        # One vessel per identifier, carrying every designation listed for
        # it, earliest first. A row repeated cell for cell is DMA listing
        # the same designation twice and is kept once.
        #
        # Rows are merged only when their name agrees too. Two names under
        # one IMO number is not something this list states about one
        # vessel, so they stay separate records with one filename, and the
        # fetch collision guard refuses them instead of publishing either.
        #
        # @param vessels [Array<Vessel>] one per row
        # @return [Array<Vessel>]
        def self.consolidate(vessels)
          vessels.group_by { |v| [v.identifier, v.vessel_name] }.map do |(_, name), rows|
            designations = rows.flat_map(&:designations)
                               .uniq { |d| [d.date_of_application, d.subject_to] }
                               .sort_by(&:sort_key)
            Vessel.new(vessel_name: name, imo_number: rows.first.imo_number, designations: designations)
          end
        end

        def self.blank?(value)
          value.nil? || value.to_s.strip.empty?
        end
        private_class_method :blank?

        # Every fetched record this source carries.
        # @return [Array<Vessel>]
        def items
          vessels || []
        end
      end
    end
  end
end
