#!/usr/bin/env ruby
# frozen_string_literal: true

# Export raw YAML data to JSON-LD format
# Usage: ruby export.rb [--sources eu,un,us,wb] [--output ../data]

require_relative 'lib/ammitto'

class Exporter
  SOURCE_MAP = {
    'eu' => { dir: 'eu-data', code: 'eu', name: 'European Union' },
    'un' => { dir: 'un-data', code: 'un', name: 'United Nations' },
    'us' => { dir: 'us-govt-data', code: 'us', name: 'United States' },
    'wb' => { dir: 'wb-data', code: 'wb', name: 'World Bank' }
  }.freeze

  def initialize(options = {})
    @output_dir = options[:output] || '../data'
    @sources = options[:sources] || SOURCE_MAP.keys
    @serializer = Ammitto::Serialization::JsonLdSerializer.new
    @stats = {}
  end

  def run
    puts 'Exporting sanctions data to JSON-LD...'
    puts "Output directory: #{@output_dir}"
    puts ''

    FileUtils.mkdir_p(@output_dir)
    FileUtils.mkdir_p(File.join(@output_dir, 'api/v1/sources'))

    all_entities = []
    all_entries = []

    @sources.each do |source_code|
      source_info = SOURCE_MAP[source_code]
      next unless source_info

      puts "Processing #{source_info[:name]}..."

      processed_dir = File.join('..', source_info[:dir], 'processed')
      next unless Dir.exist?(processed_dir)

      entities, entries = process_source(source_code, processed_dir)

      all_entities.concat(entities)
      all_entries.concat(entries)

      # Write individual source file
      write_source_file(source_code, entities, entries)

      @stats[source_code] = {
        entities: entities.length,
        entries: entries.length
      }

      puts "  - #{entities.length} entities"
      puts "  - #{entries.length} entries"
    end

    # Write combined file
    puts ''
    puts 'Writing combined file...'
    write_combined_file(all_entities, all_entries)

    # Write stats
    write_stats

    puts ''
    puts 'Export complete!'
    puts "Total entities: #{all_entities.length}"
    puts "Total entries: #{all_entries.length}"
  end

  private

  def process_source(source_code, processed_dir)
    entities = []
    entries = []

    yaml_files = Dir.glob(File.join(processed_dir, '*.yaml'))
    yaml_files.each do |yaml_file|
      data = YAML.load_file(yaml_file)
      next unless data.is_a?(Hash)

      entity, entry = convert_to_models(source_code, data, yaml_file)
      entities << entity if entity
      entries << entry if entry
    rescue StandardError => e
      puts "  Warning: Failed to process #{File.basename(yaml_file)}: #{e.message}"
    end

    [entities, entries]
  end

  def convert_to_models(source_code, data, yaml_file)
    entity_type = data['entity_type'] || 'organization'
    entity_id = generate_entity_id(source_code, data, yaml_file)

    # Create name variants
    names = (data['names'] || []).map do |name|
      Ammitto::NameVariant.new(
        full_name: name,
        is_primary: name == data['names']&.first
      )
    end

    # Create source reference
    source_ref = Ammitto::SourceReference.new(
      source_code: source_code,
      reference_number: data['ref_number']
    )

    # Create entity based on type
    entity = create_entity(entity_type, entity_id, names, source_ref, data)

    # Create sanction entry
    entry = create_entry(source_code, entity_id, data)

    [entity, entry]
  end

  def create_entity(type, id, names, source_ref, data)
    entity_class = case type
                   when 'person' then Ammitto::PersonEntity
                   when 'organization' then Ammitto::OrganizationEntity
                   when 'vessel' then Ammitto::VesselEntity
                   when 'aircraft' then Ammitto::AircraftEntity
                   else Ammitto::OrganizationEntity
                   end

    entity_class.new(
      id: id,
      entity_type: type,
      names: names,
      source_references: [source_ref],
      # Type-specific fields
      **entity_specific_fields(type, data)
    )
  end

  def entity_specific_fields(type, data)
    case type
    when 'person'
      {
        birth_info: [Ammitto::BirthInfo.new(
          date: data['birthdate'],
          country: data['country']
        )].compact,
        nationalities: data['country'] ? [data['country']] : [],
        addresses: parse_addresses(data['address']),
        identifications: parse_identifications(data['documents'])
      }
    when 'organization'
      {
        country: data['country'],
        addresses: parse_addresses(data['address']),
        identifications: parse_identifications(data['documents'])
      }
    when 'vessel'
      {
        flag_state: data['country']
      }
    when 'aircraft'
      {
        flag_state: data['country']
      }
    else
      {}
    end
  end

  def parse_addresses(address_data)
    return [] unless address_data.is_a?(Array)

    address_data.map do |addr|
      next unless addr.is_a?(Hash)

      Ammitto::Address.new(
        street: addr['street'],
        city: addr['city'],
        state: addr['state'],
        country: addr['country'],
        postal_code: addr['zip']
      )
    end.compact
  end

  def parse_identifications(doc_data)
    return [] unless doc_data.is_a?(Array)

    doc_data.map do |doc|
      next unless doc.is_a?(Hash)

      Ammitto::Identification.new(
        type: doc['type'],
        number: doc['number'],
        issuing_country: doc['country'],
        note: doc['note']
      )
    end.compact
  end

  def create_entry(source_code, entity_id, data)
    source_info = SOURCE_MAP[source_code]

    Ammitto::SanctionEntry.new(
      id: "#{entity_id}/entry/#{source_code}",
      entity_id: entity_id,
      authority: Ammitto::Authority.new(
        id: source_code,
        name: source_info[:name],
        country_code: source_code.upcase
      ),
      regime: Ammitto::SanctionRegime.new(
        code: data['regime'] || 'UNKNOWN',
        name: data['regime_name'] || 'Unknown Regime'
      ),
      period: Ammitto::TemporalPeriod.new(
        listed_date: data['listed_date'] || data['listedDate'],
        last_updated: Time.now.iso8601
      ),
      status: 'active',
      reference_number: data['ref_number'],
      remarks: data['remark'],
      raw_source_data: Ammitto::RawSourceData.new(
        source_file: File.basename(data['_source_file'] || ''),
        source_format: 'yaml'
      )
    )
  end

  def generate_entity_id(source_code, data, yaml_file)
    ref = data['ref_number'] || File.basename(yaml_file, '.yaml')
    "https://ammitto.org/entity/#{source_code}/#{ref.to_s.gsub(/[^a-zA-Z0-9\-_.]/, '-')}"
  end

  def write_source_file(source_code, entities, entries)
    output_path = File.join(@output_dir, "api/v1/sources/#{source_code}.jsonld")

    document = @serializer.serialize_document(entities: entities, entries: entries)
    json = @serializer.to_json(document)

    File.write(output_path, json)
    puts "  Written: #{output_path}"
  end

  def write_combined_file(entities, entries)
    output_path = File.join(@output_dir, 'api/v1/all.jsonld')

    document = @serializer.serialize_document(entities: entities, entries: entries)
    json = @serializer.to_json(document)

    File.write(output_path, json)
    puts "  Written: #{output_path}"
  end

  def write_stats
    output_path = File.join(@output_dir, 'api/v1/stats.json')

    stats_data = {
      exported_at: Time.now.iso8601,
      sources: @stats,
      totals: {
        entities: @stats.values.sum { |s| s[:entities] },
        entries: @stats.values.sum { |s| s[:entries] }
      }
    }

    File.write(output_path, JSON.pretty_generate(stats_data))
    puts "  Written: #{output_path}"
  end
end

# CLI
if __FILE__ == $PROGRAM_NAME
  require 'optparse'

  options = {}

  OptionParser.new do |opts|
    opts.banner = 'Usage: ruby export.rb [options]'

    opts.on('--sources x,y,z', Array, 'Sources to export (eu,un,us,wb)') do |sources|
      options[:sources] = sources
    end

    opts.on('--output DIR', String, 'Output directory') do |dir|
      options[:output] = dir
    end
  end.parse!

  Exporter.new(options).run
end
