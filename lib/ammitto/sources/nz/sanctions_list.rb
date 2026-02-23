# frozen_string_literal: true

require 'lutaml/model'
require_relative 'individual'
require_relative 'entity'
require_relative 'ship'

module Ammitto
  module Sources
    module Nz
      # SanctionsList represents the New Zealand Russia Sanctions Register
      #
      # The NZ sanctions register contains:
      # - Individuals (1850+ entries)
      # - Entities/Organizations
      # - Ships
      #
      # Source: https://www.mfat.govt.nz/assets/Countries-and-Regions/Europe/Ukraine/Russia-Sanctions-Register.xlsx
      #
      class SanctionsList < Lutaml::Model::Serializable
        attribute :individuals, Individual, collection: true
        attribute :entities, Entity, collection: true
        attribute :ships, Ship, collection: true

        # Parse XLSX file and create SanctionsList
        # @param file_path [String] path to XLSX file
        # @return [SanctionsList]
        def self.from_xlsx(file_path)
          require 'roo'

          xlsx = Roo::Spreadsheet.open(file_path)
          list = new

          # Initialize collections
          list.individuals = []
          list.entities = []
          list.ships = []

          # Parse Russia Sanctions Register sheet (individuals and entities)
          xlsx.default_sheet = 'Russia Sanctions Register'

          # Headers are in row 11, data starts at row 12
          headers = xlsx.row(11)

          (12..xlsx.last_row).each do |row_num|
            row = xlsx.row(row_num)
            next if row[0].nil? # Skip empty rows

            type = row[0].to_s.strip
            data = build_entity_data(row, headers)

            case type
            when 'Individual'
              list.individuals << Individual.from_row_data(data)
            when 'Entity'
              list.entities << Entity.from_row_data(data)
            end
          end

          # Parse Ships sheet
          if xlsx.sheets.include?('Ships')
            xlsx.default_sheet = 'Ships'
            ship_headers = xlsx.row(1)

            (2..xlsx.last_row).each do |row_num|
              row = xlsx.row(row_num)
              next if row[0].nil?

              data = build_ship_data(row, ship_headers)
              list.ships << Ship.from_row_data(data)
            end
          end

          list
        end

        # Build entity data hash from row
        def self.build_entity_data(row, headers)
          data = {}
          headers.each_with_index do |header, idx|
            next unless header

            key = header.to_s.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/^_|_$/, '')
            data[key] = row[idx]
          end
          data
        end

        # Build ship data hash from row
        def self.build_ship_data(row, headers)
          data = {}
          headers.each_with_index do |header, idx|
            next unless header

            key = header.to_s.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/^_|_$/, '')
            data[key] = row[idx]
          end
          data
        end

        # Override to_yaml to serialize properly
        def to_yaml(*)
          {
            'individuals' => individuals.map(&:to_hash),
            'entities' => entities.map(&:to_hash),
            'ships' => ships.map(&:to_hash)
          }.to_yaml
        end
      end
    end
  end
end
