#!/usr/bin/env ruby
# frozen_string_literal: true

# Standalone script to parse Japan (METI) End-User List from exported HTML
# Run from ammitto root: ruby scripts/parse_jp_end_user_list.rb

require 'nokogiri'
require 'yaml'
require 'pathname'

INPUT_FILE = Pathname.new(__dir__).parent.parent / 'data-jp' / 'reference-docs' / '20250131-jp-end-user-list.html'
OUTPUT_DIR = Pathname.new(__dir__).parent.parent / 'data-jp' / 'processed'

def parse_jp_end_user_list
  puts "Parsing #{INPUT_FILE}..."

  doc = Nokogiri::HTML(File.read(INPUT_FILE))

  entities = []

  # Find all table rows
  doc.xpath('//tr').each do |tr|
    cells = tr.xpath('.//td').map { |td| td.text.strip }

    # Skip header rows or rows with insufficient columns
    next if cells.empty?
    next if cells[0].nil? || cells[0].match?(/No\.|国名/)

    # Typical columns: No., Country, Name, Details
    # Japanese format: 国名、地域名 (Country), 氏名・名称 (Name), 通関名 (Common Name), 型式・番号 (Type/Number), 备注 (Remarks)

    next unless cells[0] =~ /^\d+$/ # Must have a number

    # Extract entity data
    name = cells[2] || cells[1]
    entity = {
      'id' => cells[0],
      'name' => name,
      'entity_type' => 'organization',
      'addresses' => [],
      'remarks' => nil
    }

    # Add country as part of remarks
    entity['remarks'] = "Country: #{cells[1]}" if cells[1] && !cells[1].empty?

    # Add additional remarks/details
    entity['remarks'] = [entity['remarks'], cells[5]].compact.join('; ') if cells[5] && !cells[5].empty?

    entities << entity
  end

  puts "Found #{entities.length} entities"

  # Write YAML files
  OUTPUT_DIR.mkpath
  entities.each do |entity|
    filename = OUTPUT_DIR / "#{entity['id']}.yaml"
    File.write(filename, entity.to_yaml)
  end

  puts "Wrote #{entities.length} YAML files to #{OUTPUT_DIR}"
end

parse_jp_end_user_list if __FILE__ == $PROGRAM_NAME
