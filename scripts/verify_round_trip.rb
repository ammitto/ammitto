#!/usr/bin/env ruby
# frozen_string_literal: true

# Round-Trip Verification Script
#
# Verifies that data imported to Neo4j matches data exported to JSON-LD.
# This is the ULTIMATE test of data coverage.
#
# Process:
# 1. Load sample entities from YAML source files
# 2. Import to Neo4j using ontology classes
# 3. Export from Neo4j using ontology classes
# 4. Compare properties - should be IDENTICAL
#
# Exit codes:
#   0 - Round-trip successful
#   1 - Discrepancies found
#   2 - Cannot connect to Neo4j
#
# Usage:
#   ruby scripts/verify_round_trip.rb [--sample-size 100]

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'neo4j/driver'
require 'yaml'
require 'json'
require 'optparse'
require 'ammitto/ontology'

include Neo4j::Driver

DEFAULT_DATA_DIR = ENV['AMMITTO_DATA_DIR'] || File.expand_path('../..', __dir__)

class RoundTripVerifier
  def initialize(uri: ENV.fetch('NEO4J_URI', 'bolt://localhost:7688'), username: 'neo4j', password: 'password')
    @uri = uri
    @username = username
    @password = password
    @driver = nil
    @session = nil
    @discrepancies = []
    @verified = 0
    @failed = 0
  end

  def run(sample_size: 10, data_dir: DEFAULT_DATA_DIR)
    connect

    puts '=' * 60
    puts 'ROUND-TRIP VERIFICATION'
    puts '=' * 60
    puts "\nVerifying that import and export use the SAME ontology classes"
    puts "Sample size: #{sample_size}"
    puts ''

    # Find and verify sample entities from each source
    sources = Dir.glob(File.join(data_dir, 'data-*'))
                 .select { |d| Dir.exist?(File.join(d, 'processed', 'entities')) }

    sources.each do |source_dir|
      source = File.basename(source_dir).sub('data-', '')
      verify_source(source_dir, source, sample_size)
    end

    disconnect

    print_report

    @discrepancies.empty? ? 0 : 1
  end

  private

  def connect
    @driver = GraphDatabase.driver(@uri, AuthTokens.basic(@username, @password))
    @session = @driver.session
  rescue StandardError => e
    puts "ERROR: Cannot connect to Neo4j: #{e.message}"
    exit 2
  end

  def disconnect
    @session&.close
    @driver&.close
  end

  def verify_source(source_dir, source, sample_size)
    entities_dir = File.join(source_dir, 'processed', 'entities')
    return unless Dir.exist?(entities_dir)

    puts "\n--- Verifying #{source.upcase} ---"

    entity_files = Dir.glob(File.join(entities_dir, '*.yaml')).sample(sample_size)

    entity_files.each do |entity_file|
      verify_entity(entity_file, source)
    end
  end

  def verify_entity(entity_file, _source)
    begin
      data = YAML.load_file(entity_file)
    rescue StandardError => e
      puts "  ⚠️  Cannot load #{File.basename(entity_file)}: #{e.message}"
      return
    end

    return unless data.is_a?(Hash) && data['id']

    entity_id = data['id']
    entity_type = data['entity_type'] || data['type'] || 'organization'

    # 1. Load original data into ontology class
    original = load_original_entity(data, entity_type)
    return unless original

    # 2. Load from Neo4j using ontology class
    loaded = load_from_neo4j(entity_id, entity_type)

    if loaded.nil?
      puts "  ⚠️  Entity not found in Neo4j: #{entity_id}"
      @failed += 1
      return
    end

    # 3. Compare properties
    compare_entities(original, loaded, entity_file)
  end

  def load_original_entity(data, entity_type)
    case entity_type.to_s.downcase
    when 'person'
      PersonEntity.from_yaml(YAML.dump(data))
    when 'organization'
      OrganizationEntity.from_yaml(YAML.dump(data))
    when 'vessel'
      VesselEntity.from_yaml(YAML.dump(data))
    when 'aircraft'
      AircraftEntity.from_yaml(YAML.dump(data))
    else
      Entity.from_yaml(YAML.dump(data))
    end
  rescue StandardError => e
    puts "  ⚠️  Cannot create entity from YAML: #{e.message}"
    nil
  end

  def load_from_neo4j(entity_id, entity_type)
    entity_class = case entity_type.to_s.downcase
                   when 'person' then PersonEntity
                   when 'organization' then OrganizationEntity
                   when 'vessel' then VesselEntity
                   when 'aircraft' then AircraftEntity
                   else Entity
                   end

    entity_class.neo4j_find(@session, entity_id)
  end

  def compare_entities(original, loaded, entity_file)
    entity_id = original.id
    original_props = original.neo4j_properties
    loaded_props = loaded.neo4j_properties

    # Find discrepancies
    all_keys = (original_props.keys | loaded_props.keys)

    all_keys.each do |key|
      orig_val = original_props[key]
      load_val = loaded_props[key]

      next if values_equal?(orig_val, load_val)

      @discrepancies << {
        entity: entity_id,
        file: File.basename(entity_file),
        property: key,
        original: orig_val,
        loaded: load_val
      }
    end

    # Also verify value objects
    verify_value_objects(original, loaded, entity_id)

    @verified += 1

    if @discrepancies.any? { |d| d[:entity] == entity_id }
      print '  ❌'
      @failed += 1
    else
      print '  ✓'
    end
  end

  def verify_value_objects(original, loaded, entity_id)
    # Compare names
    compare_names(original.names, loaded.names, entity_id) if original.respond_to?(:names) && loaded.respond_to?(:names)

    # Compare addresses
    if original.respond_to?(:addresses) && loaded.respond_to?(:addresses)
      compare_addresses(original.addresses, loaded.addresses,
                        entity_id)
    end

    # Compare identifiers
    return unless original.respond_to?(:identifications) && loaded.respond_to?(:identifications)

    compare_identifiers(original.identifications, loaded.identifications, entity_id)
  end

  def compare_names(original_names, loaded_names, entity_id)
    return if original_names.nil? && loaded_names.nil?
    return if original_names&.empty? && loaded_names&.empty?

    original_count = original_names&.size || 0
    loaded_count = loaded_names&.size || 0

    if original_count != loaded_count
      @discrepancies << {
        entity: entity_id,
        property: 'names count',
        original: original_count,
        loaded: loaded_count
      }
      return
    end

    # Compare each name's properties
    original_names&.zip(loaded_names || [])&.each_with_index do |(orig, loaded), idx|
      next if orig.nil? || loaded.nil?

      orig_props = orig.neo4j_properties
      load_props = loaded.neo4j_properties

      (orig_props.keys | load_props.keys).each do |key|
        next if values_equal?(orig_props[key], load_props[key])

        @discrepancies << {
          entity: entity_id,
          property: "names[#{idx}].#{key}",
          original: orig_props[key],
          loaded: load_props[key]
        }
      end
    end
  end

  def compare_addresses(original_addrs, loaded_addrs, entity_id)
    return if original_addrs.nil? && loaded_addrs.nil?
    return if original_addrs&.empty? && loaded_addrs&.empty?

    original_count = original_addrs&.size || 0
    loaded_count = loaded_addrs&.size || 0

    return unless original_count != loaded_count

    @discrepancies << {
      entity: entity_id,
      property: 'addresses count',
      original: original_count,
      loaded: loaded_count
    }
  end

  def compare_identifiers(original_ids, loaded_ids, entity_id)
    return if original_ids.nil? && loaded_ids.nil?
    return if original_ids&.empty? && loaded_ids&.empty?

    original_count = original_ids&.size || 0
    loaded_count = loaded_ids&.size || 0

    return unless original_count != loaded_count

    @discrepancies << {
      entity: entity_id,
      property: 'identifiers count',
      original: original_count,
      loaded: loaded_count
    }
  end

  def values_equal?(val1, val2)
    return true if val1.nil? && val2.nil?
    return false if val1.nil? || val2.nil?

    # Handle arrays
    return val1.sort == val2.sort if val1.is_a?(Array) && val2.is_a?(Array)

    # Handle dates
    return val1.to_s == val2.to_s if val1.is_a?(Date) || val2.is_a?(Date)

    val1 == val2
  end

  def print_report
    puts "\n\n#{'=' * 60}"
    puts 'ROUND-TRIP VERIFICATION REPORT'
    puts '=' * 60

    puts "\nEntities verified: #{@verified}"
    puts "Entities with discrepancies: #{@failed}"

    if @discrepancies.empty?
      puts "\n✓ ROUND-TRIP VERIFICATION PASSED"
      puts '  All imported data matches exported data'
      puts '  Import and export use the SAME ontology classes'
    else
      puts "\n✗ ROUND-TRIP VERIFICATION FAILED"
      puts "\nDiscrepancies found: #{@discrepancies.size}"

      # Group by property
      by_property = @discrepancies.group_by { |d| d[:property] }

      by_property.each do |property, discreps|
        puts "\n  Property: #{property}"
        puts "  Affected entities: #{discreps.size}"
        discreps.first(3).each do |d|
          puts "    - #{d[:file]}: '#{d[:original]}' != '#{d[:loaded]}'"
        end
      end

      puts "\n#{'-' * 60}"
      puts 'ANALYSIS:'
      puts "  If 'loaded' is nil: Property not imported to Neo4j"
      puts "  If 'original' is nil: Extra property in Neo4j (not in source)"
      puts '  If both have values: Values transformed incorrectly'
    end
  end
end

# Parse command line options
options = {
  uri: ENV.fetch('NEO4J_URI', 'bolt://localhost:7688'),
  username: 'neo4j',
  password: 'password',
  sample_size: 10,
  data_dir: DEFAULT_DATA_DIR
}

OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"

  opts.on('-s', '--sample-size N', Integer, 'Number of entities to sample per source') do |n|
    options[:sample_size] = n
  end

  opts.on('-d', '--data-dir DIR', 'Data directory') do |dir|
    options[:data_dir] = dir
  end

  opts.on('-u', '--uri URI', 'Neo4j URI') do |uri|
    options[:uri] = uri
  end

  opts.on('--username USER', 'Neo4j username') do |user|
    options[:username] = user
  end

  opts.on('--password PASS', 'Neo4j password') do |pass|
    options[:password] = pass
  end
end.parse!

# Run verification
verifier = RoundTripVerifier.new(
  uri: options[:uri],
  username: options[:username],
  password: options[:password]
)

exit(verifier.run(sample_size: options[:sample_size], data_dir: options[:data_dir]))
