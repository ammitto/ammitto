# frozen_string_literal: true

require 'lutaml/model'
require_relative 'vessel'

module Ammitto
  module Sources
    module EuVessels
      # SanctionsList represents the EU Designated Vessels list
      #
      # This list contains vessels designated under Annex XLII of
      # Council Regulation (EU) 833/2014, hosted by Danish Maritime Authority.
      #
      # Source: https://www.dma.dk/growth-and-framework-conditions/maritime-sanctions/sanctions-against-russia-and-belarus/eu-vessel-designations
      #
      class SanctionsList < Lutaml::Model::Serializable
        attribute :vessels, Vessel, collection: true

        # Parse XLSX file and create SanctionsList
        # @param file_path [String] path to XLSX file
        # @return [SanctionsList]
        def self.from_xlsx(file_path)
          require 'roo'

          xlsx = Roo::Spreadsheet.open(file_path)
          list = new
          list.vessels = []

          # Sheet name is the regulation number (8332014)
          xlsx.default_sheet = xlsx.sheets.first

          # Headers are in row 1
          headers = xlsx.row(1)

          (2..xlsx.last_row).each do |row_num|
            row = xlsx.row(row_num)
            next if row[0].nil? # Skip empty rows

            data = build_vessel_data(row, headers)
            list.vessels << Vessel.from_row_data(data)
          end

          list
        end

        # Build vessel data hash from row
        def self.build_vessel_data(row, headers)
          data = {}
          headers.each_with_index do |header, idx|
            next unless header

            # Normalize header key
            key = header.to_s.downcase.strip.gsub(/[^a-z0-9]+/, '_').gsub(/^_|_$/, '')
            data[key] = row[idx]
          end
          data
        end

        # Override to_yaml to serialize properly
        def to_yaml(*)
          {
            'vessels' => vessels.map(&:to_hash)
          }.to_yaml
        end
      end
    end
  end
end
