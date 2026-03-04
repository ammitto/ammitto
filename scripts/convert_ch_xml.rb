#!/usr/bin/env ruby
# frozen_string_literal: true

# Converter for Swiss SECO sanctions XML to normalized knowledge graph format.
#
# Usage:
#   ruby scripts/convert_ch_xml.rb /path/to/data-ch/reference-docs/consolidated-list_2026-02-18.xml /path/to/data-ch/processed

require 'yaml'
require 'fileutils'
require 'rexml/document'
require 'time'

class SwissSanctionsConverter
  def initialize(xml_path, output_dir)
    @xml_path = xml_path
    @output_dir = output_dir
    @entity_id_counter = 0
    @entities = {} # dedupe by name + birth year
    @entries = []
    @announcements = {}
    @legal_instruments = {}
    @programs = {} # sanctions-program -> regime mapping
  end

  def convert
    puts 'Parsing Swiss sanctions XML...'
    doc = REXML::Document.new(File.read(@xml_path))

    # First pass: collect programs and their ssids
    collect_programs(doc)

    # Second pass: process targets (which contain individuals)
    puts 'Processing targets...'
    doc.elements.each('//target') do |target|
      process_target(target)
    end

    # Third pass: collect objects (vessels)
    puts 'Processing vessels...'
    doc.elements.each('//object') do |obj|
      process_object(obj)
    end

    # Write output
    write_output

    puts 'Conversion complete!'
    puts "  Entities: #{@entities.size}"
    puts "  Entries: #{@entries.size}"
    puts "  Announcements: #{@announcements.size}"
    puts "  Legal Instruments: #{@legal_instruments.size}"
  end

  private

  def collect_programs(doc)
    # Build map from sanctions-set ssid -> program info
    @set_to_program = {}

    doc.elements.each('//sanctions-program') do |prog|
      ssid = prog.attributes['ssid']
      version_date = prog.attributes['version-date']

      # Get program name (English)
      name_elem = prog.elements['program-key[@lang="eng"]']
      program_name = name_elem.text if name_elem

      # Get origin
      origin = prog.elements['origin']
      origin_text = origin.text if origin

      @programs[ssid] = {
        name: program_name,
        version_date: version_date,
        origin: origin_text
      }

      # Map each sanctions-set to this program
      prog.elements.each('sanctions-set') do |sset|
        set_ssid = sset.attributes['ssid']
        @set_to_program[set_ssid] = ssid
      end
    end
    puts "  Found #{@programs.size} sanctions programs"
  end

  def process_target(target)
    # Get sanctions-set-id to find the program
    set_id_elem = target.elements['sanctions-set-id']
    return unless set_id_elem

    set_ssid = set_id_elem.text
    prog_ssid = @set_to_program[set_ssid]
    program = @programs[prog_ssid]

    # Check modification status
    status = 'active'
    target.elements.each('modification') do |mod|
      if mod.attributes['modification-type'] == 'de-listed'
        status = 'delisted'
        break
      end
    end

    # Process individual inside target
    individual = target.elements['individual']
    return unless individual

    process_individual(individual, program, status)
  end

  def process_individual(individual, program, status = 'active')
    # Get identities
    identities = individual.elements.to_a('identity')

    # Process main identity (or first)
    main_identity = identities.find { |i| i.attributes['main'] == 'true' } || identities.first
    return unless main_identity

    main_identity.attributes['ssid']

    # Extract name
    name_data = extract_name(main_identity)
    return unless name_data[:full_name]

    # Extract birth info
    birth_info = extract_birth_info(main_identity)

    # Extract nationality
    nationality = extract_nationality(main_identity)

    # Extract address
    address = extract_address(main_identity)

    # Get justification (reason for listing)
    justification = individual.elements['justification']
    reason = justification&.text

    # Get other information
    other_info = individual.elements['other-information']
    remarks = other_info&.text

    # Generate entity ID
    entity_id = generate_entity_id(name_data[:full_name], birth_info[:year])

    # Store entity
    entity = {
      'id' => entity_id,
      'entity_type' => 'person',
      'names' => [
        {
          'full_name' => name_data[:full_name],
          'name_script' => name_data[:script],
          'is_primary' => true
        }
      ].concat(name_data[:aliases].map { |a| { 'full_name' => a, 'is_primary' => false } }),
      'birth_info' => birth_info[:year] ? [birth_info] : [],
      'nationalities' => nationality ? [nationality] : [],
      'addresses' => address ? [address] : [],
      'remarks' => remarks
    }.compact

    @entities[entity_id] = entity

    # Create entry - link to the program's announcement
    return unless program

    entry_id = "entry-#{entity_id}"
    announcement_id = 'ch-consolidated-list'

    # Create announcement if not exists
    @announcements[announcement_id] ||= {
      'id' => announcement_id,
      'title' => "Swiss Sanctions - #{program[:name]}",
      'date' => program[:version_date],
      'issuing_authority' => 'SECO',
      'source_url' => 'https://www.seco.admin.ch/seco/en/home/Aussenwirtschaft_Warenhandel_aussenwirtschaft_wirtschaft-zusammenarbeit/exportkontrolle-und-sanktionen/sanktionen-embargos.html'
    }

    @entries << {
      'id' => entry_id,
      'entity_id' => entity_id,
      'announcement_id' => announcement_id,
      'status' => status,
      'list_type' => 'consolidated-list',
      'measures' => ['Asset freeze', 'Travel ban'],
      'remarks' => reason
    }.compact
  end

  def process_object(obj)
    obj_type = obj.attributes['object-type']
    return unless obj_type == 'vessel'

    # Get identity
    identity = obj.elements['identity']
    return unless identity

    ssid = identity.attributes['ssid']

    # Extract name
    name_data = extract_name(identity)
    return unless name_data[:full_name]

    # Get IMO number from other-information
    other_info = obj.elements['other-information']
    imo = nil
    if other_info&.text
      match = other_info.text.match(/IMO Number:\s*(\d+)/)
      imo = match[1] if match
    end

    # Generate entity ID
    entity_id = generate_entity_id(name_data[:full_name], nil, 'vessel')

    # Store entity
    entity = {
      'id' => entity_id,
      'entity_type' => 'vessel',
      'names' => [
        {
          'full_name' => name_data[:full_name],
          'name_script' => name_data[:script],
          'is_primary' => true
        }
      ].concat(name_data[:aliases].map { |a| { 'full_name' => a, 'is_primary' => false } }),
      'identifications' => imo ? [{ 'type' => 'IMO', 'identification' => imo }] : [],
      'remarks' => other_info&.text
    }.compact

    @entities[entity_id] = entity

    # Create entry
    entry_id = "entry-#{entity_id}-#{ssid}"
    @entries << {
      'id' => entry_id,
      'entity_id' => entity_id,
      'announcement_id' => 'ch-consolidated-list',
      'status' => 'active',
      'list_type' => 'consolidated-list',
      'measures' => ['Asset freeze']
    }.compact
  end

  def extract_name(identity)
    result = { full_name: nil, aliases: [], script: 'Latn' }

    identity.elements.each('name') do |name_elem|
      next unless name_elem.attributes['name-type'] == 'primary-name'

      # Collect name parts
      parts = []
      name_elem.elements.each('name-part') do |np|
        val = np.elements['value']
        parts << val.text if val
      end

      if parts.any?
        result[:full_name] = parts.join(' ')
        result[:script] = detect_script(name_elem)
      end

      # Get aliases
      identity.elements.each('name[@name-type="alias"]') do |alias_elem|
        alias_parts = []
        alias_elem.elements.each('name-part') do |np|
          val = np.elements['value']
          alias_parts << val.text if val
        end
        result[:aliases] << alias_parts.join(' ') if alias_parts.any?
      end
    end

    result
  end

  def detect_script(name_elem)
    # Check for Cyrillic or other scripts
    name_elem.elements.each('name-part') do |np|
      np.elements.each('spelling-variant') do |sv|
        script = sv.attributes['script']
        return 'Cyrl' if script == 'CYRL'
        return 'Hani' if script == 'HANI'
      end
    end
    'Latn'
  end

  def extract_birth_info(identity)
    result = { year: nil, place: nil, country: nil }

    dob = identity.elements['day-month-year']
    if dob
      result[:year] = dob.attributes['year']
      result[:place] = dob.elements['place']&.text
      result[:country] = dob.elements['country']&.text
    end

    result
  end

  def extract_nationality(identity)
    nat = identity.elements['nationality']
    return nil unless nat

    country = nat.elements['country']
    country&.text
  end

  def extract_address(identity)
    addr = identity.elements['address']
    return nil unless addr

    address = {}
    address['care_of'] = addr.elements['c-o']&.text
    address['street'] = addr.elements['address-details']&.text
    address['city'] = addr.elements['city']&.text
    address['zip_code'] = addr.elements['zip-code']&.text

    country = addr.elements['country']
    address['country'] = country&.text if country

    address['place'] = addr.elements['place']&.text

    address.compact.empty? ? nil : address
  end

  def generate_entity_id(name, year, prefix = nil)
    # Create a simple ID from name
    base = name.downcase
               .gsub(/[^a-z0-9]/, ' ')
               .split
               .join('-')
               .slice(0, 40)

    base = "#{prefix}-#{base}" if prefix
    base = "#{base}-#{year}" if year

    # Check for collision
    if @entities[base]
      # Add suffix
      suffix = 1
      suffix += 1 while @entities["#{base}-#{suffix}"]
      base = "#{base}-#{suffix}"
    end

    base
  end

  def write_output
    entities_dir = File.join(@output_dir, 'entities')
    entries_dir = File.join(@output_dir, 'entries')
    announcements_dir = File.join(@output_dir, 'announcements')

    FileUtils.mkdir_p(entities_dir)
    FileUtils.mkdir_p(entries_dir)
    FileUtils.mkdir_p(announcements_dir)

    # Write entities
    puts "Writing #{@entities.size} entities..."
    @entities.each do |id, data|
      File.write(File.join(entities_dir, "#{id}.yaml"), data.to_yaml)
    end

    # Write entries
    puts "Writing #{@entries.size} entries..."
    @entries.each do |data|
      File.write(File.join(entries_dir, "#{data['id']}.yaml"), data.to_yaml)
    end

    # Write announcements
    puts "Writing #{@announcements.size} announcements..."
    @announcements.each do |id, data|
      File.write(File.join(announcements_dir, "#{id}.yaml"), data.to_yaml)
    end

    # Write index
    index = {
      'source' => 'ch',
      'schema_version' => '3.0',
      'structure' => 'normalized_knowledge_graph',
      'list_types' => ['consolidated-list'],
      'generated_at' => Time.now.utc.iso8601
    }
    File.write(File.join(@output_dir, '_index.yaml'), index.to_yaml)
  end
end

# Main
if __FILE__ == $PROGRAM_NAME
  if ARGV.length < 2
    puts 'Usage: ruby convert_ch_xml.rb <xml_path> <output_dir>'
    exit 1
  end

  xml_path = ARGV[0]
  output_dir = ARGV[1]

  unless File.exist?(xml_path)
    puts "Error: XML file not found: #{xml_path}"
    exit 1
  end

  FileUtils.mkdir_p(output_dir)

  converter = SwissSanctionsConverter.new(xml_path, output_dir)
  converter.convert
end
