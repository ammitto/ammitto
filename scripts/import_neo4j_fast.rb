#!/usr/bin/env ruby
# frozen_string_literal: true

# Direct Neo4j Import - Fast Batch Version
#
# Usage:
#   ruby scripts/import_neo4j_fast.rb [options]

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'neo4j/driver'
require 'yaml'
require 'optparse'
require 'ammitto/ontology'

include Neo4j::Driver

def import_batch(batch, session)
  batch.each do |e|
    session.run(
      'MERGE (n:Entity {id: $id}) SET n.type = $type, n.source = $source, n.primary_name = $primary_name',
      id: e[:id], type: e[:type], source: e[:source], primary_name: e[:primary_name]
    )
  rescue StandardError => ex
    puts "Error importing #{e[:id]}: #{ex.message}"
  end
end

options = {
  uri: 'bolt://localhost:7688',
  username: 'neo4j',
  password: 'password',
  batch_size: 100
}

OptionParser.new do |opts|
  opts.banner = 'Usage: ruby scripts/import_neo4j_fast.rb [options]'

  opts.on('--uri=URI', 'Neo4j URI') do |u|
    options[:uri] = u
  end

  opts.on('--username=USER', 'Neo4j username') do |u|
    options[:username] = u
  end

  opts.on('--password=PASS', 'Neo4j password') do |p|
    options[:password] = p
  end
end.parse!

puts '=== Fast Neo4j Import ==='

# Connect
driver = GraphDatabase.driver(options[:uri], AuthTokens.basic(options[:username], options[:password]))
session = driver.session

# Clear and setup
puts 'Clearing existing data...'
session.run('MATCH (n) DETACH DELETE n')

puts 'Creating schema...'
session.run('CREATE CONSTRAINT IF NOT EXISTS FOR (n:Entity) REQUIRE n.id IS UNIQUE')
session.run('CREATE CONSTRAINT IF NOT EXISTS FOR (n:Entry) REQUIRE n.id IS UNIQUE')
session.run('CREATE CONSTRAINT IF NOT EXISTS FOR (n:Authority) REQUIRE n.code IS UNIQUE')
session.run('CREATE INDEX IF NOT EXISTS FOR (n:Entity) ON (n.source)')
session.run('CREATE INDEX IF NOT EXISTS FOR (n:Entity) ON (n.type)')
session.run('CREATE INDEX IF NOT EXISTS FOR (n:Entry) ON (n.status)')

# Import authorities
puts 'Importing authorities...'
Ammitto::Ontology.authorities.each do |code, auth|
  session.run(
    'MERGE (a:Authority {code: $code}) SET a.name = $name, a.country_code = $country_code',
    code: code, name: auth.name, country_code: auth.country_code
  )
end

# Find all sources
base_dir = '/Users/mulgogi/src/ammitto'
sources = Dir.glob(File.join(base_dir, 'data-*')).select { |d| Dir.exist?(File.join(d, 'processed')) }

total_entities = 0

sources.each do |src_dir|
  source = File.basename(src_dir).sub('data-', '')
  processed = File.join(src_dir, 'processed', 'entities')

  next unless Dir.exist?(processed)

  puts "Importing #{source}..."

  # Batch import entities
  batch = []
  Dir.glob(File.join(processed, '*.yaml')).each do |f|
    data = YAML.load_file(f)
    next unless data.is_a?(Hash) && data['id']

    entity_id = data['id']
    entity_type = data['entity_type'] || data['type'] || 'organization'

    # Get primary name - extract string values only from names array
    names = data['names'] || data['name_variants'] || []
    primary_name = nil
    if names.is_a?(Array) && names.any?
      # Find primary or use first
      name_obj = names.find { |n| n.is_a?(Hash) && n['is_primary'] == true } || names.first
      if name_obj.is_a?(Hash)
        # Try multiple possible keys
        primary_name = name_obj['english'] || name_obj['full_name'] || name_obj['name'] || name_obj['value']
      elsif name_obj.is_a?(String)
        primary_name = name_obj
      end
    end

    # Skip if primary_name is still a Hash (can't serialize)
    next if primary_name.is_a?(Hash)

    batch << { id: entity_id, type: entity_type, source: source, primary_name: primary_name }

    next unless batch.size >= options[:batch_size]

    import_batch(batch, session)
    total_entities += batch.size
    batch = []
  end

  import_batch(batch, session) if batch.any?
  total_entities += batch.size
end

puts "Imported #{total_entities} entities"

# Validate
puts "\n=== Validation ==="
result = session.run('MATCH (n) RETURN labels(n)[0] as type, count(n) as count ORDER BY count DESC')
result.each { |r| puts "  #{r[:type]}: #{r[:count]}" }

session.close
driver.close
puts "\nDone!"
