#!/usr/bin/env ruby
# frozen_string_literal: true

# Migration script to fix IRI structure in existing knowledge graph data.
#
# This script:
# 1. Removes source prefixes from entity IDs (e.g., "cn-mitsubishi" -> "mitsubishi")
# 2. Adds list_type to entries
# 3. Updates references to match new IDs
#
# Usage:
#   ruby scripts/migrate_iri_structure.rb /path/to/data-cn/processed
#
# Example:
#   ruby scripts/migrate_iri_structure.rb /Users/mulgogi/src/ammitto/data-cn/processed

require 'yaml'
require 'fileutils'

class IriMigrator
  attr_reader :processed_dir, :source_code, :dry_run

  def initialize(processed_dir, dry_run: false)
    @processed_dir = processed_dir
    @dry_run = dry_run
    @source_code = detect_source_code
    @id_mapping = {} # old_id -> new_id
  end

  def migrate
    puts "Migrating #{source_code} data in #{processed_dir}"
    puts "Dry run: #{dry_run}"
    puts

    # Step 1: Migrate entities
    puts '=== Migrating entities ==='
    migrate_entities

    # Step 2: Migrate entries
    puts "\n=== Migrating entries ==="
    migrate_entries

    # Step 3: Migrate announcements
    puts "\n=== Migrating announcements ==="
    migrate_announcements

    # Step 4: Migrate legal instruments
    puts "\n=== Migrating legal instruments ==="
    migrate_legal_instruments

    # Step 5: Update index
    puts "\n=== Updating index ==="
    update_index

    puts "\n=== Migration complete ==="
    puts "Entities: #{@id_mapping.select { |k, _| k.start_with?('entity:') }.size} renamed"
    puts "Entries: #{@id_mapping.select { |k, _| k.start_with?('entry:') }.size} renamed"
  end

  private

  def detect_source_code
    index_file = File.join(processed_dir, '_index.yaml')
    if File.exist?(index_file)
      index = YAML.load_file(index_file)
      return index['source'] if index && index['source']
    end

    # Fallback: extract from directory name
    dirname = File.basename(File.dirname(processed_dir))
    dirname.gsub(/^data-/, '').gsub('-', '_')
  end

  def strip_source_prefix(id)
    return id unless id

    # Remove source prefix (e.g., "cn-mitsubishi" -> "mitsubishi")
    prefix_pattern = /\A#{Regexp.escape(source_code)}-/
    stripped = id.sub(prefix_pattern, '')

    # Handle variant prefixes (e.g., un-vessels vs un-vessel)
    if stripped == id && source_code.include?('-')
      # Try removing the prefix without trailing 's' (un-vessels -> un-vessel)
      base = source_code.sub(/s\z/, '')
      alt_prefix = /\A#{Regexp.escape(base)}-/
      stripped = id.sub(alt_prefix, '')
    end

    stripped
  end

  def migrate_entities
    entities_dir = File.join(processed_dir, 'entities')
    return unless File.directory?(entities_dir)

    files = Dir.glob(File.join(entities_dir, '*.yaml'))
    files.each do |file|
      data = YAML.load_file(file)
      next unless data.is_a?(Hash) && data['id']

      old_id = data['id']
      new_id = strip_source_prefix(old_id)

      next unless old_id != new_id

      @id_mapping["entity:#{old_id}"] = new_id

      # Update data
      data['id'] = new_id

      # Write new file
      new_file = File.join(entities_dir, "#{new_id}.yaml")

      puts "  #{old_id} -> #{new_id}"

      unless dry_run
        File.write(new_file, data.to_yaml)
        File.delete(file) if file != new_file
      end
    end
  end

  def migrate_entries
    entries_dir = File.join(processed_dir, 'entries')
    return unless File.directory?(entries_dir)

    # Determine list_type from source code
    list_type = determine_list_type

    files = Dir.glob(File.join(entries_dir, '*.yaml'))
    files.each do |file|
      data = YAML.load_file(file)
      next unless data.is_a?(Hash)

      old_id = data['id']
      old_entity_id = data['entity_id']
      needs_write = false

      # Update entity_id reference
      new_entity_id = @id_mapping["entity:#{old_entity_id}"] || strip_source_prefix(old_entity_id)
      if data['entity_id'] != new_entity_id
        data['entity_id'] = new_entity_id
        needs_write = true
      end

      # Add list_type if missing
      unless data['list_type']
        data['list_type'] = list_type
        needs_write = true
      end

      # Generate new entry ID (simplified, without redundant prefixes)
      new_local_id = new_entity_id
      new_id = "entry-#{new_local_id}"

      if old_id != new_id
        @id_mapping["entry:#{old_id}"] = new_id
        data['id'] = new_id

        # Update legal_instrument_ids references
        if data['legal_instrument_ids']
          new_legal_ids = data['legal_instrument_ids'].map do |li_id|
            @id_mapping["legal_instrument:#{li_id}"] || strip_source_prefix(li_id)
          end
          data['legal_instrument_ids'] = new_legal_ids if new_legal_ids != data['legal_instrument_ids']
        end

        # Update announcement_id reference
        if data['announcement_id']
          new_ann_id = @id_mapping["announcement:#{data['announcement_id']}"] || data['announcement_id']
          data['announcement_id'] = new_ann_id if new_ann_id != data['announcement_id']
        end

        puts "  #{old_id} -> #{new_id}"

        new_file = File.join(entries_dir, "#{new_id}.yaml")
        File.write(new_file, data.to_yaml)
        File.delete(file) if file != new_file
      elsif needs_write
        # File needs update (e.g., for list_type) but ID didn't change
        File.write(file, data.to_yaml)
      end
    end
  end

  def migrate_announcements
    announcements_dir = File.join(processed_dir, 'announcements')
    return unless File.directory?(announcements_dir)

    files = Dir.glob(File.join(announcements_dir, '*.yaml'))
    files.each do |file|
      data = YAML.load_file(file)
      next unless data.is_a?(Hash) && data['id']

      old_id = data['id']
      new_id = strip_source_prefix(old_id)

      next unless old_id != new_id

      @id_mapping["announcement:#{old_id}"] = new_id
      data['id'] = new_id

      puts "  #{old_id} -> #{new_id}"

      next if dry_run

      new_file = File.join(announcements_dir, "#{new_id}.yaml")
      File.write(new_file, data.to_yaml)
      File.delete(file) if file != new_file
    end
  end

  def migrate_legal_instruments
    instruments_dir = File.join(processed_dir, 'legal_instruments')
    return unless File.directory?(instruments_dir)

    files = Dir.glob(File.join(instruments_dir, '*.yaml'))
    files.each do |file|
      data = YAML.load_file(file)
      next unless data.is_a?(Hash) && data['id']

      old_id = data['id']
      new_id = strip_source_prefix(old_id)

      next unless old_id != new_id

      @id_mapping["legal_instrument:#{old_id}"] = new_id
      data['id'] = new_id

      puts "  #{old_id} -> #{new_id}"

      next if dry_run

      new_file = File.join(instruments_dir, "#{new_id}.yaml")
      File.write(new_file, data.to_yaml)
      File.delete(file) if file != new_file
    end
  end

  def determine_list_type
    # Map source codes to their primary list type
    list_type_map = {
      'au' => 'consolidated-list',
      'ca' => 'consolidated-list',
      'ch' => 'consolidated-list',
      'cn' => 'import-export-control-list',
      'eu' => 'consolidated-list',
      'eu-vessels' => 'vessel-sanctions-list',
      'jp' => 'end-user-list',
      'nz' => 'consolidated-list',
      'ru' => 'stop-list',
      'tr' => 'consolidated-list',
      'uk' => 'consolidated-list',
      'un' => 'consolidated-list',
      'un-vessels' => 'vessel-sanctions-list',
      'us' => 'sdn-list',
      'wb' => 'debarment-list'
    }

    list_type_map[source_code] || 'consolidated-list'
  end

  def update_index
    index_file = File.join(processed_dir, '_index.yaml')
    return unless File.exist?(index_file)

    index = YAML.load_file(index_file)
    return unless index

    # Update schema version
    index['schema_version'] = '3.0'
    index['structure'] = 'normalized_knowledge_graph'

    # Add list_types if not present
    index['list_types'] ||= [determine_list_type]

    puts '  Updated schema_version to 3.0'

    return if dry_run

    File.write(index_file, index.to_yaml)
  end
end

# Main
if __FILE__ == $PROGRAM_NAME
  if ARGV.empty?
    puts 'Usage: ruby scripts/migrate_iri_structure.rb /path/to/data-xxx/processed [--dry-run]'
    exit 1
  end

  processed_dir = ARGV[0]
  dry_run = ARGV.include?('--dry-run')

  unless File.directory?(processed_dir)
    puts "Error: Directory not found: #{processed_dir}"
    exit 1
  end

  migrator = IriMigrator.new(processed_dir, dry_run: dry_run)
  migrator.migrate
end
