#!/usr/bin/env ruby
# frozen_string_literal: true

# Standalone script to parse Russia MID sanctions from reference-docs
# Run from ammitto root: ruby scripts/parse_ru_sanctions_list.rb

require 'yaml'
require 'pathname'

REF_DOCS_DIR = Pathname.new(__dir__).parent.parent / 'data-ru' / 'reference-docs'
OUTPUT_DIR = Pathname.new(__dir__).parent.parent / 'data-ru' / 'processed'

def parse_ru_sanctions
  entities = []
  entity_index = 0

  # Parse full-list files (consolidated lists by country)
  full_list_dir = REF_DOCS_DIR / 'full-list'
  if full_list_dir.exist?
    full_list_dir.glob('*.md').each do |file|
      puts "Parsing #{file.basename}..."
      file_entities = parse_full_list_file(file)
      file_entities.each do |entity|
        entity_index += 1
        entity['id'] = "RU-#{entity_index.to_s.rjust(4, '0')}"
        entities << entity
      end
      puts "  Found #{file_entities.length} entities"
    end
  end

  # Parse announcement files (individual sanctions announcements)
  announcements_dir = REF_DOCS_DIR / 'announcements'
  if announcements_dir.exist?
    announcements_dir.glob('*.md').each do |file|
      puts "Parsing #{file.basename}..."
      file_entities = parse_announcement_file(file)
      file_entities.each do |entity|
        entity_index += 1
        entity['id'] = "RU-#{entity_index.to_s.rjust(4, '0')}"
        entities << entity
      end
      puts "  Found #{file_entities.length} entities"
    end
  end

  puts "\nTotal entities: #{entities.length}"

  # Write YAML files
  OUTPUT_DIR.mkpath

  # Clear existing files
  OUTPUT_DIR.glob('RU-*.yaml').each(&:delete)

  entities.each do |entity|
    filename = OUTPUT_DIR / "#{entity['id']}.yaml"
    File.write(filename, entity.to_yaml)
  end

  puts "Wrote #{entities.length} YAML files to #{OUTPUT_DIR}"
end

def parse_full_list_file(file)
  entities = []
  content = File.read(file)

  # Extract country from filename (e.g., uk-20240410.md -> UK)
  country = file.basename('.md').to_s.split('-').first.upcase

  lines = content.lines

  lines.each do |line|
    line = line.strip
    next if line.empty?
    next if line.start_with?('#')
    next if line.start_with?('http')
    next if line.start_with?('По состоянию') # "As of" date line
    next if line.match?(/^\d{2}\.\d{2}\.\d{4}/) # Date lines

    # Pattern: Russian Name (English NAME) - title
    # or: Russian NAME (English NAME) - title
    match = line.match(/^(.+?)\s*\((.+?)\)\s*[—–-]\s*(.+)$/)
    if match
      russian_name = clean_name(match[1])
      english_name = clean_name(match[2])
      title = clean_title(match[3])

      entities << build_entity(russian_name, english_name, title, country, 'person')
      next
    end

    # Pattern: Russian Name (English NAME) without title
    match = line.match(/^(.+?)\s*\((.+?)\)$/)
    if match
      russian_name = clean_name(match[1])
      english_name = clean_name(match[2])

      entities << build_entity(russian_name, english_name, nil, country, 'person')
      next
    end

    # Pattern: English NAME - title (without Russian)
    match = line.match(/^([A-Z][A-Za-z\s]+)\s*[—–-]\s*(.+)$/)
    next unless match

    english_name = clean_name(match[1])
    title = clean_title(match[2])

    entities << build_entity(nil, english_name, title, country, 'person')
    next
  end

  entities
end

def parse_announcement_file(file)
  entities = []
  content = File.read(file)

  lines = content.lines

  # Extract metadata
  lines.first&.strip if lines.first&.start_with?('http')
  date_match = content.match(/(\d{2})\.(\d{2})\.(\d{4})/)
  date_match ? "#{date_match[3]}-#{date_match[2]}-#{date_match[1]}" : nil

  # Extract announcement number
  number_match = content.match(/(\d+)-\d{2}-\d{2}-\d{4}/)
  number_match ? number_match[1] : nil

  current_entity_type = 'person'

  lines.each do |line|
    line = line.strip
    next if line.empty?
    next if line.start_with?('#')
    next if line.start_with?('http')
    next if line.start_with?('*') # Skip bullet notes
    next if line.start_with?('В ') # Skip Russian prose
    next if line.start_with?('In ') # Skip English prose
    next if line.start_with?('The ') # Skip English prose
    next if line.start_with?('This ') # Skip English prose
    next if line.start_with?('We ') # Skip English prose
    next if line.start_with?('London') # Skip prose
    next if line.start_with?('Ниже') # Skip prose

    # Detect entity type changes
    if line.include?('Физические') || line.include?('граждане') || line.include?('лиц')
      current_entity_type = 'person'
    elsif line.include?('Юридические') || line.include?('организации') || line.include?('компании')
      current_entity_type = 'organization'
    end

    # Pattern: Numbered list with bilingual name and title
    # "1. Russian Name (English Name), title" or
    # "1. Russian Name (English Name) – title" or
    # "1. English Name, title"
    match = line.match(/^\d+\.\s*(.+?)\s*\((.+?)\)\s*[,—–-]\s*(.+)$/)
    if match
      russian_name = clean_name(match[1])
      english_name = clean_name(match[2])
      title = clean_title(match[3])

      entities << build_entity(russian_name, english_name, title, nil, current_entity_type)
      next
    end

    # Pattern: Numbered list with bilingual name (no title)
    match = line.match(/^\d+\.\s*(.+?)\s*\((.+?)\)$/)
    if match
      russian_name = clean_name(match[1])
      english_name = clean_name(match[2])

      entities << build_entity(russian_name, english_name, nil, nil, current_entity_type)
      next
    end

    # Pattern: Numbered list with English name and title
    match = line.match(/^\d+\.\s*([A-Z][A-Za-z\s]+),\s*(.+)$/)
    if match
      english_name = clean_name(match[1])
      title = clean_title(match[2])

      entities << build_entity(nil, english_name, title, nil, current_entity_type)
      next
    end

    # Pattern: Numbered list with English name and semicolon title
    match = line.match(/^\d+\.\s*([A-Z][A-Za-z\s]+)\s*;\s*(.+)$/)
    if match
      english_name = clean_name(match[1])
      title = clean_title(match[2])

      entities << build_entity(nil, english_name, title, nil, current_entity_type)
      next
    end

    # Pattern: Numbered list with just English name (no title)
    match = line.match(/^\d+\.\s*([A-Z][A-Za-z\s]+)$/)
    next unless match

    english_name = clean_name(match[1])

    entities << build_entity(nil, english_name, nil, nil, current_entity_type)
    next
  end

  entities
end

def build_entity(russian_name, english_name, title, country, entity_type)
  names = []

  if russian_name && !russian_name.empty?
    names << { 'full_name' => russian_name, 'script' => 'Cyrl',
               'is_primary' => english_name.nil? || english_name.empty? }
  end

  if english_name && !english_name.empty?
    names << { 'full_name' => english_name, 'script' => 'Latn',
               'is_primary' => true }
  end

  entity = {
    'entity_type' => entity_type || 'person',
    'names' => names,
    'list_type' => 'stop_list',
    'source' => 'ru'
  }

  entity['title'] = title if title && !title.empty?
  entity['country'] = country if country

  entity
end

def clean_name(name)
  return nil if name.nil?

  name.strip.gsub(/\s+/, ' ')
end

def clean_title(title)
  return nil if title.nil?

  title.strip.gsub(/\s+/, ' ').gsub(/[;.]$/, '')
end

parse_ru_sanctions if __FILE__ == $PROGRAM_NAME
