#!/usr/bin/env ruby
# frozen_string_literal: true

# Standalone script to parse UN 1718 Committee Vessel List from exported HTML
# Run from ammitto root: ruby scripts/parse_un_vessels_list.rb

require 'nokogiri'
require 'yaml'
require 'pathname'

INPUT_FILE = Pathname.new(__dir__).parent.parent / 'data-un-vessels' / 'reference-docs' / '1718_designated_vessels_list_final.html'
OUTPUT_DIR = Pathname.new(__dir__).parent.parent / 'data-un-vessels' / 'processed'

def parse_un_vessels_list
  puts "Parsing #{INPUT_FILE}..."

  doc = Nokogiri::HTML(File.read(INPUT_FILE))

  vessels = []

  # Find all tables with vessel information
  doc.xpath('//table').each do |table|
    rows = table.xpath('.//tr')

    rows.each do |row|
      cells = row.xpath('.//td').map { |td| td.text.strip }

      # Skip empty rows
      next if cells.empty?
      next if cells[0].nil?

      # Skip header rows
      next if cells[0].match?(/Vessel Name|IMO Number|#/)

      # Skip "Otherinformation" rows - they contain additional details
      next if cells[0] == 'Otherinformation'

      # Skip rows that don't have vessel data (e.g., resolution references)
      next unless cells[1]&.include?(':')

      # Extract vessel name from format "1: VESSEL NAME"
      vessel_name = cells[1].split(': ', 2).last&.strip
      next unless vessel_name && !vessel_name.empty?

      # Extract IMO number from cells[2]
      imo_number = cells[2]&.strip
      # Skip if IMO is not a valid number
      next if imo_number.nil? || imo_number.empty? || !imo_number.match?(/^\d+$/)

      # Generate ID from IMO number
      vessel_id = "un-vessel-#{imo_number}"

      vessel = {
        'id' => vessel_id,
        'entity_type' => 'vessel',
        'names' => [
          { 'full_name' => vessel_name, 'is_primary' => true }
        ]
      }

      # Add IMO number
      vessel['imo_number'] = imo_number

      # Add date designated (cells[3])
      vessel['date_designated'] = cells[3] if cells[3] && !cells[3].empty? && cells[3] != 'na'

      vessels << vessel
    end
  end

  puts "Found #{vessels.length} vessels"

  # Write YAML files
  OUTPUT_DIR.mkpath

  # Clear existing files (except index)
  OUTPUT_DIR.glob('*.yaml').each(&:delete)
  OUTPUT_DIR.glob('un-vessel-*.yaml').each(&:delete)

  vessels.each do |vessel|
    filename = OUTPUT_DIR / "#{vessel['id']}.yaml"
    File.write(filename, vessel.to_yaml)
  end

  puts "Wrote #{vessels.length} YAML files to #{OUTPUT_DIR}"
end

parse_un_vessels_list if __FILE__ == $PROGRAM_NAME
