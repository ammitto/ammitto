#!/usr/bin/env ruby
# frozen_string_literal: true

# Neo4j Data Validation Script
#
# Validates data completeness and relationship integrity in Neo4j.
# This ensures that the ontology classes' declarations match what's in Neo4j.
#
# Checks performed:
# 1. Property coverage - all declared properties exist in Neo4j nodes
# 2. Relationship integrity - all relationships point to valid nodes
# 3. Orphan detection - nodes without required relationships
# 4. Cross-link validity - country references, authority references, etc.
#
# Exit codes:
#   0 - All validations passed
#   1 - Validation errors found
#   2 - Cannot connect to Neo4j
#
# Usage:
#   ruby scripts/validate_neo4j_data.rb [--uri bolt://localhost:7688]

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'neo4j/driver'
require 'optparse'
require 'ammitto/ontology'

include Neo4j::Driver

class Neo4jDataValidator
  VALIDATION_TYPES = %w[all schema integrity orphans coverage].freeze

  def initialize(uri: ENV.fetch('NEO4J_URI', 'bolt://localhost:7688'), username: 'neo4j', password: 'password')
    @uri = uri
    @username = username
    @password = password
    @driver = nil
    @session = nil
    @errors = []
    @warnings = []
    @checks_run = []
  end

  def run(validation_types: ['all'])
    validations = validation_types.include?('all') ? VALIDATION_TYPES - ['all'] : validation_types

    connect

    validations.each do |type|
      send("validate_#{type}")
      @checks_run << type
    end

    disconnect

    print_report

    @errors.empty? ? 0 : 1
  end

  private

  def connect
    @driver = GraphDatabase.driver(@uri, AuthTokens.basic(@username, @password))
    @session = @driver.session
  rescue StandardError => e
    puts "ERROR: Cannot connect to Neo4j: #{e.message}"
    exit 2
  ensure
    @session&.close
    @driver&.close
  end

  # ======================================================================
  # SCHEMA VALIDATION
  # Check that all declared properties exist in Neo4j nodes
  # ======================================================================

  def validate_schema
    puts "\n#{'=' * 60}"
    puts 'SCHEMA VALIDATION'
    puts '=' * 60

    # Validate entity properties
    validate_entity_properties(PersonEntity, 'Person')
    validate_entity_properties(OrganizationEntity, 'Organization')
    validate_entity_properties(VesselEntity, 'Vessel')
    validate_entity_properties(AircraftEntity, 'Aircraft')

    # Validate value object properties
    validate_value_object_properties(NameVariant, 'Name')
    validate_value_object_properties(Address, 'Address')
    validate_value_object_properties(Identification, 'Identifier')
    validate_value_object_properties(BirthInfo, 'BirthInfo')
  end

  def validate_entity_properties(entity_class, label)
    declared = entity_class.all_neo4j_property_attributes
    puts "\n  #{label} Entity:"
    puts "    Declared properties: #{declared.join(', ')}"

    result = @session.run("MATCH (n:#{label}) RETURN keys(n) as props LIMIT 1")

    if result.any?
      existing = result.first[:props]
      missing = declared.map(&:to_s) - existing
      extra = existing - declared.map(&:to_s) - ['id']

      puts "    Properties in Neo4j: #{existing.join(', ')}"

      if missing.any?
        @errors << "SCHEMA: #{label} - missing properties in Neo4j: #{missing.join(', ')}"
        puts "    ❌ Missing in Neo4j: #{missing.join(', ')}"
      else
        puts '    ✓ All declared properties exist'
      end

      if extra.any?
        @warnings << "SCHEMA: #{label} - extra properties in Neo4j (not declared): #{extra.join(', ')}"
        puts "    ⚠️  Extra (not declared): #{extra.join(', ')}"
      end
    else
      puts "    No #{label} nodes found"
    end
  end

  def validate_value_object_properties(value_class, label)
    declared = value_class.all_neo4j_property_attributes
    puts "\n  #{label}:"
    puts "    Declared properties: #{declared.join(', ')}"

    result = @session.run("MATCH (n:#{label}) RETURN keys(n) as props LIMIT 1")

    if result.any?
      existing = result.first[:props]
      missing = declared.map(&:to_s) - existing

      puts "    Properties in Neo4j: #{existing.join(', ')}"

      if missing.any?
        @errors << "SCHEMA: #{label} - missing properties in Neo4j: #{missing.join(', ')}"
        puts "    ❌ Missing in Neo4j: #{missing.join(', ')}"
      else
        puts '    ✓ All declared properties exist'
      end
    else
      puts "    No #{label} nodes found"
    end
  end

  # ======================================================================
  # RELATIONSHIP INTEGRITY
  # Check that all relationships point to valid nodes
  # ======================================================================

  def validate_integrity
    puts "\n#{'=' * 60}"
    puts 'RELATIONSHIP INTEGRITY'
    puts '=' * 60

    check_entity_has_name
    check_entity_has_address
    check_entity_has_identifier
    check_entry_has_entity
    check_entry_has_authority
    check_name_in_country
    check_address_in_country
    check_identifier_issued_by_country
  end

  def check_entity_has_name
    result = @session.run(
      'MATCH (e:Entity) WHERE NOT (e)-[:HAS_NAME]->(:Name) RETURN e.id as id'
    )
    orphans = result.to_a

    if orphans.any?
      @errors << "INTEGRITY: #{orphans.size} entities have no names"
      puts "\n  ❌ Entities without names: #{orphans.size}"
      orphans.first(5).each { |o| puts "      #{o[:id]}" }
    else
      puts "\n  ✓ All entities have names"
    end
  end

  def check_entity_has_address
    result = @session.run(
      'MATCH (e:Entity) WHERE NOT (e)-[:HAS_ADDRESS]->(:Address) RETURN e.id as id'
    )
    orphans = result.to_a

    if orphans.any?
      @warnings << "INTEGRITY: #{orphans.size} entities have no addresses"
      puts "\n  ⚠️  Entities without addresses: #{orphans.size}"
      orphans.first(5).each { |o| puts "      #{o[:id]}" }
    else
      puts "\n  ✓ All entities have addresses (or addresses are optional)"
    end
  end

  def check_entity_has_identifier
    result = @session.run(
      'MATCH (e:Entity) WHERE NOT (e)-[:HAS_IDENTIFIER]->(:Identifier) RETURN e.id as id'
    )
    orphans = result.to_a

    if orphans.any?
      @warnings << "INTEGRITY: #{orphans.size} entities have no identifiers"
      puts "\n  ⚠️  Entities without identifiers: #{orphans.size}"
      orphans.first(5).each { |o| puts "      #{o[:id]}" }
    else
      puts "\n  ✓ All entities have identifiers (or identifiers are optional)"
    end
  end

  def check_entry_has_entity
    result = @session.run(
      'MATCH (e:Entry) WHERE NOT (e)-[:FOR_ENTITY]->(:Entity) RETURN e.id as id'
    )
    orphans = result.to_a

    if orphans.any?
      @errors << "INTEGRITY: #{orphans.size} entries have no entity"
      puts "\n  ❌ Entries without entities: #{orphans.size}"
      orphans.first(5).each { |o| puts "      #{o[:id]}" }
    else
      puts "\n  ✓ All entries have entities"
    end
  end

  def check_entry_has_authority
    result = @session.run(
      'MATCH (e:Entry) WHERE NOT (e)-[:LISTED_BY]->(:Authority) RETURN e.id as id'
    )
    orphans = result.to_a

    if orphans.any?
      @errors << "INTEGRITY: #{orphans.size} entries have no authority"
      puts "\n  ❌ Entries without authorities: #{orphans.size}"
      orphans.first(5).each { |o| puts "      #{o[:id]}" }
    else
      puts "\n  ✓ All entries have authorities"
    end
  end

  def check_name_in_country
    result = @session.run(
      'MATCH (n:Name) WHERE NOT (n)-[:IN_COUNTRY]->(:Country) RETURN n.id as id LIMIT 10'
    )
    orphans = result.to_a

    if orphans.any?
      @warnings << 'INTEGRITY: Some names have no country'
      puts "\n  ⚠️  Names without countries: #{orphans.size}"
    else
      puts "\n  ✓ Names have countries (or country is optional)"
    end
  end

  def check_address_in_country
    result = @session.run(
      'MATCH (a:Address) WHERE NOT (a)-[:IN_COUNTRY]->(:Country) RETURN a.id as id'
    )
    orphans = result.to_a

    if orphans.any?
      @errors << "INTEGRITY: #{orphans.size} addresses have no country"
      puts "\n  ❌ Addresses without countries: #{orphans.size}"
      orphans.first(5).each { |o| puts "      #{o[:id]}" }
    else
      puts "\n  ✓ All addresses have countries"
    end
  end

  def check_identifier_issued_by_country
    result = @session.run(
      'MATCH (i:Identifier) WHERE NOT (i)-[:ISSUED_BY]->(:Country) RETURN i.id as id'
    )
    orphans = result.to_a

    if orphans.any?
      @warnings << "INTEGRITY: #{orphans.size} identifiers have no issuing country"
      puts "\n  ⚠️  Identifiers without issuing countries: #{orphans.size}"
    else
      puts "\n  ✓ All identifiers have issuing countries (or optional)"
    end
  end

  # ======================================================================
  # ORPHAN DETECTION
  # Find nodes without required relationships
  # ======================================================================

  def validate_orphans
    puts "\n#{'=' * 60}"
    puts 'ORPHAN DETECTION'
    puts '=' * 60

    check_orphan_names
    check_orphan_addresses
    check_orphan_identifiers
    check_orphan_entries
  end

  def check_orphan_names
    result = @session.run(
      'MATCH (n:Name) WHERE NOT (n)<-[:HAS_NAME]-() RETURN count(n) as count'
    )
    count = result.first[:count]

    if count.positive?
      @errors << "ORPHANS: #{count} orphaned names"
      puts "\n  ❌ Orphaned Name nodes: #{count}"
    else
      puts "\n  ✓ No orphaned Name nodes"
    end
  end

  def check_orphan_addresses
    result = @session.run(
      'MATCH (a:Address) WHERE NOT (a)<-[:HAS_ADDRESS]-() RETURN count(a) as count'
    )
    count = result.first[:count]

    if count.positive?
      @errors << "ORPHANS: #{count} orphaned addresses"
      puts "\n  ❌ Orphaned Address nodes: #{count}"
    else
      puts "\n  ✓ No orphaned Address nodes"
    end
  end

  def check_orphan_identifiers
    result = @session.run(
      'MATCH (i:Identifier) WHERE NOT (i)<-[:HAS_IDENTIFIER]-() RETURN count(i) as count'
    )
    count = result.first[:count]

    if count.positive?
      @errors << "ORPHANS: #{count} orphaned identifiers"
      puts "\n  ❌ Orphaned Identifier nodes: #{count}"
    else
      puts "\n  ✓ No orphaned Identifier nodes"
    end
  end

  def check_orphan_entries
    result = @session.run(
      'MATCH (e:Entry) WHERE NOT (e)<-[:FOR_ENTITY]-() RETURN count(e) as count'
    )
    count = result.first[:count]

    if count.positive?
      @errors << "ORPHANS: #{count} orphaned entries"
      puts "\n  ❌ Orphaned Entry nodes: #{count}"
    else
      puts "\n  ✓ No orphaned Entry nodes"
    end
  end

  # ======================================================================
  # COVERAGE METRICS
  # Report on data completeness
  # ======================================================================

  def validate_coverage
    puts "\n#{'=' * 60}"
    puts 'COVERAGE METRICS'
    puts '=' * 60

    puts "\n  Node counts:"
    result = @session.run(
      'MATCH (n) RETURN labels(n)[0] as type, count(n) as count ORDER BY count DESC'
    )
    result.each do |row|
      puts "    #{row[:type]}: #{row[:count]}"
    end

    puts "\n  Relationship counts:"
    result = @session.run(
      'MATCH ()-[r]->() RETURN type(r) as type, count(r) as count ORDER BY count DESC'
    )
    result.each do |row|
      puts "    #{row[:type]}: #{row[:count]}"
    end

    # Calculate completeness scores
    puts "\n  Completeness scores:"
    calculate_completeness('Person', 'full_name')
    calculate_completeness('Name', 'is_primary')
    calculate_completeness('Address', 'city')
    calculate_completeness('Identifier', 'number')
  end

  def calculate_completeness(label, key_property)
    total = @session.run("MATCH (n:#{label}) RETURN count(n) as count").first[:count]
    return if total.zero?

    with_property = @session.run(
      "MATCH (n:#{label}) WHERE n.#{key_property} IS NOT NULL RETURN count(n) as count"
    ).first[:count]

    percentage = (with_property.to_f / total * 100).round(1)
    status = if percentage >= 80
               '✓'
             else
               (percentage >= 50 ? '⚠️' : '❌')
             end

    puts "    #{label}.#{key_property}: #{percentage}% (#{with_property}/#{total}) #{status}"
  end

  # ======================================================================
  # REPORTING
  # ======================================================================

  def print_report
    puts "\n#{'=' * 60}"
    puts 'VALIDATION SUMMARY'
    puts '=' * 60
    puts "\nChecks run: #{@checks_run.join(', ')}"
    puts "\nErrors: #{@errors.size}"
    @errors.each { |e| puts "  ❌ #{e}" }

    puts "\nWarnings: #{@warnings.size}"
    @warnings.each { |w| puts "  ⚠️  #{w}" }

    puts "\n#{'-' * 60}"

    if @errors.empty?
      puts '✓ VALIDATION PASSED'
    else
      puts "✗ VALIDATION FAILED with #{@errors.size} errors"
    end
  end
end

# Parse command line options
options = {
  uri: ENV.fetch('NEO4J_URI', 'bolt://localhost:7688'),
  username: 'neo4j',
  password: 'password',
  validations: ['all']
}

OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"

  opts.on('-t', '--type TYPES', Array,
          "Validation types: #{Neo4jDataValidator::VALIDATION_TYPES.join(', ')}") do |types|
    options[:validations] = types
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

# Run validation
validator = Neo4jDataValidator.new(
  uri: options[:uri],
  username: options[:username],
  password: options[:password]
)

exit(validator.run(validation_types: options[:validations]))
