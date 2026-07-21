#!/usr/bin/env ruby
# frozen_string_literal: true

# Universal converter for data-* repositories to NORMALIZED knowledge graph format.
#
# == Normalized Directory Structure
#
#   processed/
#   ├── entities/                      # NORMALIZED - unique per source
#   │   ├── marco-rubio.yaml           # Local ID only
#   │   └── mitsubishi-heavy-industries.yaml
#   ├── entries/                       # Links entity to list via list_type field
#   │   ├── entry-marco-rubio-anti-sanction.yaml
#   │   └── entry-mitsubishi-import-export.yaml
#   ├── announcements/                 # NORMALIZED - can affect multiple lists
#   │   └── mofcom-2026-11.yaml
#   ├── legal_instruments/             # NORMALIZED - can authorize multiple lists
#   │   └── export-control-law.yaml
#   ├── lists/                         # List definitions
#   │   ├── anti-sanction-list.yaml
#   │   └── import-export-control-list.yaml
#   └── _index.yaml
#
# == IRI Structure
#
#   # Entities - LIST-AGNOSTIC (can be on multiple lists)
#   https://www.ammitto.org/entity/{source}/{local_id}
#
#   # Entries - LIST-SPECIFIC (junction records)
#   https://www.ammitto.org/entry/{source}/{list_type}/{local_id}
#
# == Usage
#
#   # Simple conversion (single list)
#   ruby scripts/convert_to_knowledge_graph.rb au /path/to/data-au/processed
#
#   # With list type
#   ruby scripts/convert_to_knowledge_graph.rb cn /path/to/data-cn/processed \
#       --list-type import-export-control-list

require 'yaml'
require 'fileutils'
require 'json'
require 'optparse'

class KnowledgeGraphConverter
  # List type configurations per source
  LIST_TYPE_CONFIGS = {
    'cn' => {
      'anti-sanction-list' => {
        name: 'Anti-Sanction List',
        name_chinese: '反制裁清单',
        authority: 'MFA',
        legal_instruments: ['anti-sanction-law']
      },
      'import-export-control-list' => {
        name: 'Import-Export Control List',
        name_chinese: '出口管制管控名单',
        authority: 'MOFCOM',
        legal_instruments: %w[export-control-law foreign-trade-law]
      },
      'unreliable-entity-list' => {
        name: 'Unreliable Entity List',
        name_chinese: '不可靠实体清单',
        authority: 'MOFCOM',
        legal_instruments: ['foreign-trade-law']
      }
    },
    'ru' => {
      'stop-list' => {
        name: 'Stop List',
        name_russian: 'Стоп-лист',
        authority: 'MID',
        legal_instruments: ['federal-law-sanctions']
      }
    }
  }.freeze

  # Default list type per source
  DEFAULT_LIST_TYPES = {
    'au' => 'consolidated-list',
    'ca' => 'consolidated-list',
    'ch' => 'consolidated-list',
    'eu' => 'consolidated-list',
    'eu-vessels' => 'vessel-sanctions-list',
    'jp' => 'end-user-list',
    'nz' => 'consolidated-list',
    'tr' => 'consolidated-list',
    'uk' => 'consolidated-list',
    'un' => 'consolidated-list',
    'un-vessels' => 'vessel-sanctions-list',
    'us' => 'sdn-list',
    'wb' => 'debarment-list'
  }.freeze

  # Source-specific configurations
  SOURCE_CONFIGS = {
    'au' => {
      name: 'Australia (DFAT)',
      authority: 'DFAT',
      legal_instruments: [
        { id: 'charter-un-sanctions-taliban', name: 'Charter of the UN (Sanctions—Taliban) Regulation 2013' },
        { id: 'autonomous-sanctions-act', name: 'Autonomous Sanctions Act 2011' }
      ]
    },
    'ca' => {
      name: 'Canada (Global Affairs)',
      authority: 'Global Affairs Canada',
      legal_instruments: [
        { id: 'sema', name: 'Special Economic Measures Act' },
        { id: 'jvcia', name: 'Justice for Victims of Corrupt Foreign Officials Act' }
      ]
    },
    'ch' => {
      name: 'Switzerland (SECO)',
      authority: 'SECO',
      legal_instruments: [
        { id: 'embargo-act', name: 'Federal Act on the Implementation of International Sanctions' }
      ]
    },
    'eu' => {
      name: 'European Union',
      authority: 'European Commission',
      legal_instruments: [
        { id: 'cfsp', name: 'Common Foreign and Security Policy' },
        { id: 'council-regulations', name: 'Council Regulations on Restrictive Measures' }
      ]
    },
    'eu-vessels' => {
      name: 'EU Vessels',
      authority: 'European Commission',
      legal_instruments: [
        { id: 'council-regulation-765-2006', name: 'Council Regulation (EC) No 765/2006' }
      ]
    },
    'jp' => {
      name: 'Japan (METI)',
      authority: 'METI',
      legal_instruments: [
        { id: 'fetas', name: 'Foreign Exchange and Foreign Trade Act' }
      ]
    },
    'nz' => {
      name: 'New Zealand (MFAT)',
      authority: 'MFAT',
      legal_instruments: [
        { id: 'sanctions-act', name: 'Sanctions Act 2018' },
        { id: 'un-sanctions-act', name: 'United Nations Sanctions Act 1946' }
      ]
    },
    'tr' => {
      name: 'Turkey (HMB)',
      authority: 'HMB',
      legal_instruments: [
        { id: 'law-7262', name: 'Law No. 7262 on Prevention of Financing of Proliferation of WMD' }
      ]
    },
    'uk' => {
      name: 'United Kingdom (OFSI)',
      authority: 'OFSI',
      legal_instruments: [
        { id: 'sanctions-act', name: 'Sanctions and Anti-Money Laundering Act 2018' }
      ]
    },
    'un' => {
      name: 'United Nations',
      authority: 'UN Security Council',
      legal_instruments: [
        { id: 'charter-chapter-vii', name: 'UN Charter Chapter VII' },
        { id: 'resolution-1267', name: 'UN Security Council Resolution 1267 (1999)' }
      ]
    },
    'un-vessels' => {
      name: 'UN Vessels',
      authority: 'UN Security Council',
      legal_instruments: [
        { id: 'resolution-1718', name: 'UN Security Council Resolution 1718 (2006)' }
      ]
    },
    'us' => {
      name: 'United States (OFAC)',
      authority: 'OFAC',
      legal_instruments: [
        { id: 'ieepa', name: 'International Emergency Economic Powers Act' },
        { id: 'ndaa', name: 'National Defense Authorization Act' }
      ]
    },
    'wb' => {
      name: 'World Bank',
      authority: 'World Bank',
      legal_instruments: [
        { id: 'procurement-guidelines', name: 'Procurement Guidelines' }
      ]
    }
  }.freeze

  attr_reader :source_code, :processed_dir, :list_type, :config

  def initialize(source_code, processed_dir, list_type: nil)
    @source_code = source_code
    @processed_dir = processed_dir
    @list_type = list_type || DEFAULT_LIST_TYPES[source_code]
    @config = load_config

    create_directories
  end

  def convert
    puts "Converting #{source_code}#{" (#{list_type})" if list_type}..."

    # Create lists
    create_lists

    # Create legal instruments
    create_legal_instruments

    # Create announcement
    create_announcement

    # Convert entities
    entity_files = Dir.glob(File.join(processed_dir, '*.yaml')).reject { |f| f.include?('_index') }

    entity_count = 0
    entry_count = 0

    entity_files.each do |file|
      data = YAML.load_file(file)
      next unless data.is_a?(Hash)

      entity_id = extract_entity_id(file, data)
      next unless entity_id

      # Create entity
      entity_data = build_entity(data, entity_id)
      next unless entity_data

      write_yaml("entities/#{entity_id}.yaml", entity_data)
      entity_count += 1

      # Create entry
      entry_data = build_entry(data, entity_id)
      entry_id = "entry-#{entity_id}#{"-#{list_type}" if list_type}"
      entry_data['id'] = entry_id
      write_yaml("entries/#{entry_id}.yaml", entry_data)
      entry_count += 1
    end

    # Update index
    update_index(entity_count, entry_count)

    puts "  Created #{entity_count} entities, #{entry_count} entries"
    { entities: entity_count, entries: entry_count }
  end

  def cleanup_old_files
    # Remove old YAML files from root (keep subdirectories and _index.yaml)
    Dir.glob(File.join(processed_dir, '*.yaml')).each do |file|
      next if File.basename(file) == '_index.yaml'

      File.delete(file)
    end
  end

  # Get available list types for a source
  def self.available_list_types(source_code)
    LIST_TYPE_CONFIGS[source_code]&.keys || []
  end

  private

  def load_config
    # Check for list-type specific config
    if list_type && LIST_TYPE_CONFIGS[source_code]
      list_config = LIST_TYPE_CONFIGS[source_code][list_type]
      return list_config if list_config
    end

    # Fall back to source config
    SOURCE_CONFIGS[source_code] || default_config
  end

  def default_config
    {
      name: "#{source_code.upcase} Sanctions",
      authority: source_code.upcase,
      legal_instruments: []
    }
  end

  def create_directories
    %w[entities entries announcements legal_instruments lists].each do |dir|
      FileUtils.mkdir_p(File.join(processed_dir, dir))
    end
  end

  def create_lists
    available_lists = LIST_TYPE_CONFIGS[source_code] || {}

    if available_lists.empty?
      # Create default list
      list_data = {
        'id' => list_type || 'consolidated-list',
        'source' => source_code,
        'name' => config[:name] || config['name'] || "#{source_code.upcase} Sanctions List",
        'authority' => config[:authority] || config['authority'] || source_code.upcase,
        'legal_instrument_ids' => (config[:legal_instruments] || config['legal_instruments'] || []).map do |li|
          li[:id] || li['id']
        end
      }
      write_yaml("lists/#{list_data['id']}.yaml", list_data)
    else
      # Create all lists for this source
      available_lists.each do |list_id, list_info|
        list_data = {
          'id' => list_id,
          'source' => source_code,
          'name' => list_info[:name] || list_info['name'],
          'name_chinese' => list_info[:name_chinese] || list_info['name_chinese'],
          'name_russian' => list_info[:name_russian] || list_info['name_russian'],
          'authority' => list_info[:authority] || list_info['authority'],
          'legal_instrument_ids' => list_info[:legal_instruments] || list_info['legal_instruments'] || []
        }.compact
        write_yaml("lists/#{list_id}.yaml", list_data)
      end
    end
  end

  def create_legal_instruments
    instruments = config[:legal_instruments] || config['legal_instruments'] || []
    instruments.each do |li|
      li_id = li[:id] || li['id']
      li_name = li[:name] || li['name']

      data = {
        'id' => li_id,
        'name_english' => li_name,
        'enacted_date' => '2000-01-01'
      }.compact
      write_yaml("legal_instruments/#{li_id}.yaml", data)
    end
  end

  def create_announcement
    ann_id = announcement_id
    data = {
      'id' => ann_id,
      'number' => ann_id,
      'title' => config[:name] || config['name'] || "#{source_code.upcase} Sanctions List",
      'date' => Time.now.utc.strftime('%Y-%m-%d'),
      'effective_date' => Time.now.utc.strftime('%Y-%m-%d'),
      'issuing_authority' => config[:authority] || config['authority'] || source_code.upcase,
      'legal_instruments' => (config[:legal_instruments] || config['legal_instruments'] || []).map do |li|
        li[:id] || li['id']
      end,
      'measures' => ['Sanctions measures as applicable'],
      'reason' => 'National security and foreign policy'
    }.compact
    write_yaml("announcements/#{ann_id}.yaml", data)
  end

  def announcement_id
    "#{source_code}-announcement"
  end

  def extract_entity_id(file, data)
    basename = File.basename(file, '.yaml')

    # Extract the local ID - REMOVE source prefix if present
    local_id = case source_code
               when 'au'
                 data['reference'] || basename.gsub(/^au-/, '')
               when 'ca'
                 name = data['given_name'] || data['last_name'] || basename
                 sanitize_local_id(name)
               when 'ch'
                 data['ssid'] || basename.gsub(/^ch-/, '')
               when 'eu'
                 basename.gsub(/^eu-/, '')
               when 'eu-vessels'
                 data['imo_number'] || basename.gsub(/^eu-vessel-/, '')
               when 'jp'
                 data['id'] || basename.gsub(/^jp-/, '')
               when 'nz'
                 data['unique_identifier']&.downcase&.gsub('ent-', '') || basename.gsub(/^nz-/, '')
               when 'tr'
                 data['reference_number'] || basename.gsub(/^tr-/, '')
               when 'uk'
                 data['unique_id']&.downcase || basename
               when 'un'
                 data['ref_number']&.gsub('.', '-')&.downcase || basename.gsub(/^un-/, '')
               when 'un-vessels'
                 data['id'] || basename
               when 'us'
                 basename
               when 'wb'
                 basename
               when 'cn'
                 basename.gsub(/^cn-/, '')
               else
                 basename.gsub(/^#{source_code}-/, '')
               end

    sanitize_local_id(local_id)
  end

  # Sanitize a string for use as a local identifier.
  def sanitize_local_id(str)
    return 'unknown' if str.nil? || str.to_s.strip.empty?

    str.to_s
       .gsub(/\s+/, '-')
       .gsub(/[^a-zA-Z0-9\-_]/, '')
       .gsub(/--+/, '-')
       .gsub(/^-|-$/, '')
       .downcase
       .slice(0, 64)
       .tap { |s| s.replace('unknown') if s.empty? }
  end

  def build_entity(data, entity_id)
    names = extract_names(data)
    return nil if names.empty?

    entity_type = extract_entity_type(data)

    entity = {
      'id' => entity_id,
      'type' => entity_type,
      'names' => names
    }

    # Add source references
    entity['source_references'] = [{
      'source_code' => source_code,
      'reference_number' => extract_reference(data)
    }]

    # Add type-specific details
    case entity_type
    when 'person'
      entity['person_details'] = extract_person_details(data)
    when 'organization'
      entity['organization_details'] = extract_organization_details(data)
    when 'vessel'
      entity['vessel_details'] = extract_vessel_details(data)
    end

    # Add remarks
    entity['remarks'] = extract_remarks(data)

    entity
  end

  def build_entry(data, entity_id)
    {
      'entity_id' => entity_id,
      'list_type' => list_type,
      'announcement_id' => announcement_id,
      'legal_instrument_ids' => (config[:legal_instruments] || config['legal_instruments'] || []).map do |li|
        li[:id] || li['id']
      end,
      'measures' => extract_measures(data),
      'status' => 'active',
      'listed_date' => extract_listed_date(data)
    }.compact
  end

  def extract_names(data)
    names = []

    case source_code
    when 'au'
      (data['names'] || []).each do |n|
        names << { 'english' => n['text'], 'is_primary' => n['name_type'] == 'Primary Name' }
      end
    when 'ca'
      full_name = [data['given_name'], data['last_name']].compact.map(&:strip).join(' ')
      names << { 'english' => full_name, 'is_primary' => true } if full_name && !full_name.empty?
    when 'eu'
      (data['names'] || []).each do |n|
        names << { 'english' => n, 'is_primary' => names.empty? }
      end
    when 'uk'
      (data.dig('names', 'names') || []).each do |n|
        names << { 'english' => n['name6'], 'is_primary' => n['name_type'] == 'Primary Name' }
      end
    when 'un', 'us'
      (data['names'] || []).each do |n|
        names << { 'english' => n, 'is_primary' => names.empty? }
      end
    when 'un-vessels'
      (data['names'] || []).each do |n|
        names << { 'english' => n['full_name'], 'is_primary' => n['is_primary'] }
      end
    when 'eu-vessels'
      names << { 'english' => data['vessel_name'], 'is_primary' => true } if data['vessel_name']
    when 'nz'
      names << { 'english' => data['name'], 'is_primary' => true } if data['name']
      if data['alias_alternate_spellings']
        names << { 'english' => data['alias_alternate_spellings'],
                   'is_primary' => false }
      end
    when 'wb'
      (data['names'] || []).each do |n|
        names << { 'english' => n, 'is_primary' => names.empty? }
      end
    else
      names << { 'english' => data['name'] || data['names']&.first, 'is_primary' => true }
    end

    names.reject { |n| n['english'].nil? || n['english'].to_s.strip.empty? }
  end

  def extract_entity_type(data)
    type = data['entity_type'] || data['type'] || data['individual_entity_ship']

    return 'vessel' if source_code == 'eu-vessels'

    case type&.downcase
    when 'person', 'individual'
      'person'
    when 'organization', 'entity', 'company', 'business'
      'organization'
    when 'vessel', 'ship'
      'vessel'
    when 'aircraft'
      'aircraft'
    else
      'organization'
    end
  end

  def extract_person_details(data)
    details = {}

    if data['birthdate']
      details['date_of_birth'] = data['birthdate']
    elsif data['dates_of_birth']
      dob = data['dates_of_birth'].first
      details['date_of_birth'] = dob['raw_value'] if dob
    end

    if data['citizenships']
      details['nationality'] = data['citizenships'].first
    elsif data['country']
      details['nationality'] = data['country']
    end

    details
  end

  def extract_organization_details(data)
    details = {}

    details['country_of_registration'] = data['country'] if data['country']

    details
  end

  def extract_vessel_details(data)
    details = {}

    details['imo_number'] = data['imo_number'] if data['imo_number']

    details
  end

  def extract_reference(data)
    data['reference'] || data['ref_number'] || data['reference_number'] ||
      data['unique_id'] || data['unique_identifier'] || data['ssid'] || data['id']
  end

  def extract_remarks(data)
    data['remark'] || data['remarks'] || data['additional_info'] || data['other_information']
  end

  def extract_measures(data)
    measures = []

    case source_code
    when 'au'
      measures << 'Asset freeze' if data.dig('sanction', 'targeted_financial_sanction')
      measures << 'Travel ban' if data.dig('sanction', 'travel_ban')
      measures << 'Arms embargo' if data.dig('sanction', 'arms_embargo')
    when 'nz'
      measures << 'Asset freeze' if data['asset_freeze'] == 'Yes'
      measures << 'Travel ban' if data['travel_ban'] == 'Yes'
    else
      measures << 'Sanctions measures as applicable'
    end

    measures.empty? ? ['Sanctions measures as applicable'] : measures
  end

  def extract_listed_date(data)
    date = data['date_of_listing'] || data['date_of_sanction'] || data['listed_date'] ||
           data['date_designated'] || data['date_of_application']

    if date
      date.to_s.gsub('/', '-')
    else
      '2024-01-01'
    end
  end

  def write_yaml(relative_path, data)
    path = File.join(processed_dir, relative_path)
    File.write(path, data.to_yaml)
  end

  def update_index(entity_count, entry_count)
    index_data = {
      'source' => source_code,
      'schema_version' => '3.0',
      'structure' => 'normalized_knowledge_graph',
      'list_types' => (LIST_TYPE_CONFIGS[source_code]&.keys || [list_type]).compact,
      'counts' => {
        'entities' => entity_count,
        'entries' => entry_count,
        'announcements' => 1,
        'legal_instruments' => (config[:legal_instruments] || config['legal_instruments'] || []).length,
        'lists' => (LIST_TYPE_CONFIGS[source_code]&.keys || [list_type]).compact.length
      },
      'fetched_at' => Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
      'last_announcement' => announcement_id
    }.compact

    write_yaml('_index.yaml', index_data)
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  options = { list_type: nil }

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: ruby #{$PROGRAM_NAME} [options] <source_code> <processed_dir>"

    opts.on('--list-type TYPE', 'List type (e.g., import-export-control-list)') do |type|
      options[:list_type] = type
    end

    opts.on('-h', '--help', 'Show this help message') do
      puts opts
      puts "\nAvailable list types per source:"
      KnowledgeGraphConverter::LIST_TYPE_CONFIGS.each do |source, types|
        puts "  #{source}: #{types.keys.join(', ')}"
      end
      exit
    end
  end

  parser.parse!

  source_code = ARGV[0]
  processed_dir = ARGV[1]

  unless source_code && processed_dir
    puts parser.help
    exit 1
  end

  # Validate list type if specified
  if options[:list_type]
    available = KnowledgeGraphConverter.available_list_types(source_code)
    if available.any? && !available.include?(options[:list_type])
      puts "Error: Invalid list type '#{options[:list_type]}' for source '#{source_code}'"
      puts "Available list types: #{available.join(', ')}"
      exit 1
    end
  end

  converter = KnowledgeGraphConverter.new(source_code, processed_dir, list_type: options[:list_type])
  converter.convert
  converter.cleanup_old_files

  puts "Conversion complete for #{source_code}"
  exit 0
end
