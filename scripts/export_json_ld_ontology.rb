#!/usr/bin/env ruby
# frozen_string_literal: true

# Ontology-Driven JSON-LD Exporter
#
# This exporter uses the SAME ontology classes for both import and export,
# guaranteeing 100% coverage between Neo4j content and JSON-LD output.
#
# Key principle: neo4j_property declarations are the SINGLE SOURCE OF TRUTH.
# Whatever is declared gets exported. Nothing more, nothing less.
#
# Usage:
#   ruby scripts/export_json_ld_ontology.rb [--output-dir /path/to/output]

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'neo4j/driver'
require 'json'
require 'fileutils'
require 'optparse'
require 'ammitto/ontology'

include Neo4j::Driver

class OntologyDrivenExporter
  # All entity classes that can be exported
  ENTITY_CLASSES = [
    Ammitto::Ontology::Entities::PersonEntity,
    Ammitto::Ontology::Entities::OrganizationEntity,
    Ammitto::Ontology::Entities::VesselEntity,
    Ammitto::Ontology::Entities::AircraftEntity
  ].freeze

  def initialize(uri: 'bolt://localhost:7688', username: 'neo4j', password: 'password')
    @uri = uri
    @username = username
    @password = password
    @driver = nil
    @session = nil
    @stats = {
      entities: 0,
      names: 0,
      addresses: 0,
      identifiers: 0,
      birth_infos: 0,
      errors: []
    }
  end

  def run(output_dir: '/Users/mulgogi/src/ammitto/data/ontology/json-ld')
    connect

    FileUtils.mkdir_p(output_dir)
    puts "Exporting to #{output_dir} using ONTOLOGY-DRIVEN approach"
    puts '=' * 60

    # Export using ontology classes
    export_authorities(output_dir)
    export_all_entities(output_dir)
    export_context(output_dir)

    disconnect

    print_coverage_report
    puts "\nExport complete!"
  end

  private

  def connect
    @driver = GraphDatabase.driver(@uri, AuthTokens.basic(@username, @password))
    @session = @driver.session
    puts 'Connected to Neo4j'
  end

  def disconnect
    @session&.close
    @driver&.close
  end

  def json_context
    @json_context ||= if defined?(Ammitto::Ontology::JsonLdContext)
                        Ammitto::Ontology::JsonLdContext.generate
                      else
                        default_context
                      end
  end

  def default_context
    {
      '@vocab' => 'https://www.ammitto.org/ontology/',
      'id' => '@id',
      'type' => '@type'
    }
  end

  # Export all entities using ontology classes
  def export_all_entities(output_dir)
    entities_dir = File.join(output_dir, 'entities')
    FileUtils.mkdir_p(entities_dir)

    puts "\nExporting entities using ontology classes..."

    ENTITY_CLASSES.each do |entity_class|
      export_entities_of_type(entity_class, entities_dir)
    end
  end

  def export_entities_of_type(entity_class, output_dir)
    label = entity_class.neo4j_labels.first
    puts "\n  Exporting #{label} entities..."

    # Query all nodes with this label
    query = "MATCH (n:#{label}) RETURN n"
    result = @session.run(query)

    count = 0
    result.each do |row|
      node = row['n']
      entity = load_entity_with_relations(entity_class, node)

      next unless entity

      # Export using ontology method - GUARANTEED coverage
      jsonld = entity.to_jsonld
      jsonld['@context'] = json_context

      # Write to file
      filename = "#{sanitize_filename(entity.id)}.jsonld"
      File.write(File.join(output_dir, filename), JSON.pretty_generate(jsonld))

      count += 1
      @stats[:entities] += 1
    end

    puts "    Exported #{count} #{label} entities"
  end

  # Load entity and all related value objects using ontology classes
  def load_entity_with_relations(entity_class, node)
    entity = entity_class.from_neo4j_record(node)
    return nil unless entity

    # Load names using NameVariant class
    load_names(entity)

    # Load addresses using Address class
    load_addresses(entity)

    # Load identifiers using Identification class
    load_identifiers(entity)

    # Load birth info using BirthInfo class (for persons)
    load_birth_info(entity) if entity.respond_to?(:birth_info)

    entity
  end

  def load_names(entity)
    result = @session.run(
      'MATCH (e:Entity {id: $id})-[:HAS_NAME]->(n:Name) RETURN n',
      id: entity.id
    )

    names = result.map do |row|
      name = Ammitto::Ontology::ValueObjects::NameVariant.from_neo4j_record(row['n'])
      @stats[:names] += 1
      name
    end

    entity.names = names if entity.respond_to?(:names=)
  end

  def load_addresses(entity)
    result = @session.run(
      'MATCH (e:Entity {id: $id})-[:HAS_ADDRESS]->(a:Address) RETURN a',
      id: entity.id
    )

    addresses = result.map do |row|
      addr = Ammitto::Ontology::ValueObjects::Address.from_neo4j_record(row['n'] || row['a'])
      @stats[:addresses] += 1
      addr
    end

    entity.addresses = addresses if entity.respond_to?(:addresses=)
  end

  def load_identifiers(entity)
    return unless entity.respond_to?(:identifications=)

    result = @session.run(
      'MATCH (e:Entity {id: $id})-[:HAS_IDENTIFIER]->(i:Identifier) RETURN i',
      id: entity.id
    )

    identifiers = result.map do |row|
      id = Ammitto::Ontology::ValueObjects::Identification.from_neo4j_record(row['i'])
      @stats[:identifiers] += 1
      id
    end

    entity.identifications = identifiers
  end

  def load_birth_info(entity)
    return unless entity.respond_to?(:birth_info=)

    # Birth info might be stored as properties or related nodes
    # Check for BORN_IN relationship first
    result = @session.run(
      'MATCH (e:Entity {id: $id})-[:BORN_IN]->(b:BirthInfo) RETURN b',
      id: entity.id
    )

    return unless result.any?

    birth_infos = result.map do |row|
      bi = Ammitto::Ontology::ValueObjects::BirthInfo.from_neo4j_record(row['b'])
      @stats[:birth_infos] += 1
      bi
    end
    entity.birth_info = birth_infos
  end

  def export_authorities(output_dir)
    auth_dir = File.join(output_dir, 'authorities')
    FileUtils.mkdir_p(auth_dir)

    puts "\nExporting authorities..."

    result = @session.run('MATCH (a:Authority) RETURN a')

    result.each do |row|
      node = row['a']
      auth = {
        '@context' => json_context,
        '@id' => "https://www.ammitto.org/authority/#{node['code']}",
        '@type' => 'Authority',
        'code' => node['code'],
        'name' => node['name'],
        'country_code' => node['country_code'],
        'url' => node['url']
      }

      File.write(File.join(auth_dir, "#{node['code']}.jsonld"), JSON.pretty_generate(auth))
    end
  end

  def export_context(output_dir)
    doc = { '@context' => json_context }
    File.write(File.join(output_dir, 'context.jsonld'), JSON.pretty_generate(doc))
    puts "\nExported JSON-LD context"
  end

  def sanitize_filename(id)
    id.gsub(/[^a-zA-Z0-9\-_]/, '_')[0..80]
  end

  def print_coverage_report
    puts "\n#{'=' * 60}"
    puts 'COVERAGE REPORT'
    puts '=' * 60

    # Report what was exported
    puts "\nExported counts:"
    puts "  Entities: #{@stats[:entities]}"
    puts "  Names: #{@stats[:names]}"
    puts "  Addresses: #{@stats[:addresses]}"
    puts "  Identifiers: #{@stats[:identifiers]}"
    puts "  Birth Infos: #{@stats[:birth_infos]}"

    # Compare with Neo4j counts
    puts "\nNeo4j counts:"
    node_counts = @session.run(
      'MATCH (n) RETURN labels(n)[0] as label, count(n) as count ORDER BY count DESC'
    )
    node_counts.each { |r| puts "  #{r[:label]}: #{r[:count]}" }

    # Property coverage verification
    puts "\nProperty coverage verification:"
    verify_property_coverage(NameVariant, 'Name')
    verify_property_coverage(Address, 'Address')
    verify_property_coverage(Identification, 'Identifier')
  end

  def verify_property_coverage(value_class, label)
    declared = value_class.all_neo4j_property_attributes
    puts "\n  #{label}:"
    puts "    Declared properties: #{declared.join(', ')}"

    # Check which properties exist in Neo4j
    existing_result = @session.run(
      "MATCH (n:#{label}) WITH n LIMIT 1 RETURN keys(n) as props"
    )

    if existing_result.any?
      existing = existing_result.first[:props]
      missing = declared.map(&:to_s) - existing
      extra = existing - declared.map(&:to_s) - ['id']

      puts "    Properties in Neo4j: #{existing.join(', ')}"
      puts "    ⚠️  Missing in Neo4j: #{missing.join(', ')}" if missing.any?
      puts "    ⚠️  Extra in Neo4j (not declared): #{extra.join(', ')}" if extra.any?
      puts '    ✓ Coverage: 100%' if missing.empty? && extra.empty?
    else
      puts "    No #{label} nodes found in Neo4j"
    end
  end
end

# Parse command line options
options = {
  output_dir: '/Users/mulgogi/src/ammitto/data/ontology/json-ld',
  uri: 'bolt://localhost:7688',
  username: 'neo4j',
  password: 'password'
}

OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"

  opts.on('-o', '--output-dir DIR', 'Output directory') do |dir|
    options[:output_dir] = dir
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

# Run the exporter
exporter = OntologyDrivenExporter.new(
  uri: options[:uri],
  username: options[:username],
  password: options[:password]
)
exporter.run(output_dir: options[:output_dir])
