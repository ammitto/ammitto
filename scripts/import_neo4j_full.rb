#!/usr/bin/env ruby
# frozen_string_literal: true

# FULL Neo4j Importer - Imports ALL data to create complete knowledge graph
#
# This importer creates:
# - Entity nodes (Person, Organization, Vessel, Aircraft)
# - Name nodes with HAS_NAME relationships
# - Address nodes with HAS_ADDRESS and IN_COUNTRY relationships
# - Identifier nodes with HAS_IDENTIFIER and ISSUED_BY relationships
# - Entry nodes with FOR_ENTITY and LISTED_BY relationships
# - Authority nodes
# - Country nodes
#
# Usage:
#   ruby scripts/import_neo4j_full.rb

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'neo4j/driver'
require 'yaml'
require 'json'
require 'ammitto/ontology'

include Neo4j::Driver

class FullNeo4jImporter
  BATCH_SIZE = 100

  def initialize(uri: ENV.fetch('NEO4J_URI', 'bolt://localhost:7688'), username: 'neo4j', password: 'password')
    @uri = uri
    @username = username
    @password = password
    @driver = nil
    @session = nil
    @stats = { nodes: {}, relationships: {} }
  end

  def run
    connect
    setup_schema
    clear_existing_data

    import_countries
    import_authorities
    import_all_sources

    validate_data
    print_stats
  ensure
    disconnect
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

  def setup_schema
    puts 'Setting up schema...'

    constraints = [
      'CREATE CONSTRAINT IF NOT EXISTS FOR (n:Entity) REQUIRE n.id IS UNIQUE',
      'CREATE CONSTRAINT IF NOT EXISTS FOR (n:Entry) REQUIRE n.id IS UNIQUE',
      'CREATE CONSTRAINT IF NOT EXISTS FOR (n:Authority) REQUIRE n.code IS UNIQUE',
      'CREATE CONSTRAINT IF NOT EXISTS FOR (n:Name) REQUIRE n.id IS UNIQUE',
      'CREATE CONSTRAINT IF NOT EXISTS FOR (n:Address) REQUIRE n.id IS UNIQUE',
      'CREATE CONSTRAINT IF NOT EXISTS FOR (n:Identifier) REQUIRE n.id IS UNIQUE',
      'CREATE CONSTRAINT IF NOT EXISTS FOR (n:Country) REQUIRE n.code IS UNIQUE',
      'CREATE CONSTRAINT IF NOT EXISTS FOR (n:Regime) REQUIRE n.code IS UNIQUE',
      'CREATE CONSTRAINT IF NOT EXISTS FOR (n:Announcement) REQUIRE n.id IS UNIQUE'
    ]

    constraints.each { |c| @session.run(c) }

    indexes = [
      'CREATE INDEX IF NOT EXISTS FOR (n:Entity) ON (n.source)',
      'CREATE INDEX IF NOT EXISTS FOR (n:Entity) ON (n.type)',
      'CREATE INDEX IF NOT EXISTS FOR (n:Entity) ON (n.primary_name)',
      'CREATE INDEX IF NOT EXISTS FOR (n:Entry) ON (n.status)',
      'CREATE INDEX IF NOT EXISTS FOR (n:Name) ON (n.full_name)'
    ]

    indexes.each { |i| @session.run(i) }
    puts 'Schema created'
  end

  def clear_existing_data
    puts 'Clearing existing data...'
    @session.run('MATCH (n) DETACH DELETE n')
  end

  def import_countries
    puts 'Importing countries...'
    # ISO 3166-1 alpha-2 codes - load from a basic set
    countries = load_iso_countries

    countries.each do |code, name|
      @session.run('MERGE (c:Country {code: $code}) SET c.name = $name', code: code, name: name)
    end

    @stats[:nodes]['Country'] = countries.size
    puts "  Imported #{countries.size} countries"
  end

  def import_authorities
    puts 'Importing authorities...'

    Ammitto::Ontology.authorities.each do |code, auth|
      @session.run(
        'MERGE (a:Authority {code: $code}) SET a.name = $name, a.country_code = $country_code, a.url = $url',
        code: code, name: auth.name, country_code: auth.country_code, url: auth.url
      )
    end

    @stats[:nodes]['Authority'] = Ammitto::Ontology.authorities.size
    puts "  Imported #{Ammitto::Ontology.authorities.size} authorities"
  end

  def import_all_sources
    base_dir = ENV['AMMITTO_DATA_DIR'] || File.expand_path('../..', __dir__)
    sources = Dir.glob(File.join(base_dir, 'data-*')).select { |d| Dir.exist?(File.join(d, 'processed')) }

    sources.each do |src_dir|
      source = File.basename(src_dir).sub('data-', '')
      puts "\n=== Importing #{source} ==="

      processed = File.join(src_dir, 'processed')
      import_source(processed, source)
    end
  end

  def import_source(processed_dir, source)
    entities_dir = File.join(processed_dir, 'entities')
    entries_dir = File.join(processed_dir, 'entries')

    return unless Dir.exist?(entities_dir)

    entity_count = 0
    name_count = 0
    address_count = 0
    identifier_count = 0
    entry_count = 0

    # Import entities and their related data
    Dir.glob(File.join(entities_dir, '*.yaml')).each do |f|
      data = YAML.load_file(f)
      next unless data.is_a?(Hash) && data['id']

      entity_id = data['id']
      entity_type = data['entity_type'] || data['type'] || 'organization'

      # Get primary name
      names = data['names'] || data['name_variants'] || []
      primary_name = extract_primary_name(names)

      # Create entity node with proper label
      label = type_to_label(entity_type)
      @session.run(
        "MERGE (e:Entity {id: $id}) SET e:#{label}, e.source = $source, e.type = $type, e.primary_name = $primary_name, e.remarks = $remarks",
        id: entity_id, source: source, type: entity_type, primary_name: primary_name, remarks: data['remarks']
      )
      entity_count += 1

      # Create Name nodes
      names.each_with_index do |name_data, idx|
        full_name = nil

        if name_data.is_a?(Hash)
          # Handle nested structure like jp: {english: {full_name: ..., is_primary: ...}, is_primary: ...}
          if name_data['english'].is_a?(Hash)
            full_name = name_data['english']['full_name']
            is_primary = name_data['english']['is_primary'] || name_data['is_primary']
            script = name_data['english']['script']
          else
            full_name = name_data['english'] || name_data['full_name'] || name_data['name']
            is_primary = name_data['is_primary']
            script = name_data['script']
          end
          language = name_data['language']
        elsif name_data.is_a?(String)
          full_name = name_data
          is_primary = idx.zero?
          script = nil
          language = nil
        end

        next unless full_name.is_a?(String) && !full_name.empty?

        name_id = "#{entity_id}/name/#{idx}"

        @session.run(
          'MERGE (n:Name {id: $id}) SET n.full_name = $full_name, n.is_primary = $is_primary, n.script = $script, n.language = $language',
          id: name_id, full_name: full_name, is_primary: is_primary, script: script, language: language
        )

        @session.run(
          'MATCH (e:Entity {id: $entity_id}), (n:Name {id: $name_id}) MERGE (e)-[:HAS_NAME]->(n)',
          entity_id: entity_id, name_id: name_id
        )
        name_count += 1
      end

      # Create Address nodes
      addresses = data['addresses'] || []
      addresses.each_with_index do |addr_data, idx|
        next unless addr_data.is_a?(Hash)

        addr_id = "#{entity_id}/address/#{idx}"

        @session.run(
          'MERGE (a:Address {id: $id}) SET a.street = $street, a.city = $city, a.state = $state, a.postal_code = $postal_code',
          id: addr_id, street: addr_data['street'], city: addr_data['city'], state: addr_data['state'], postal_code: addr_data['postal_code']
        )

        @session.run(
          'MATCH (e:Entity {id: $entity_id}), (a:Address {id: $addr_id}) MERGE (e)-[:HAS_ADDRESS]->(a)',
          entity_id: entity_id, addr_id: addr_id
        )
        address_count += 1

        # Country relationship
        country = addr_data['country_code'] || addr_data['country']
        next unless country.is_a?(String) && country.length == 2

        @session.run(
          'MATCH (a:Address {id: $addr_id}), (c:Country {code: $code}) MERGE (a)-[:IN_COUNTRY]->(c)',
          addr_id: addr_id, code: country.upcase
        )
      end

      # Create Identifier nodes
      identifiers = data['identifications'] || data['identifiers'] || []
      identifiers.each_with_index do |id_data, idx|
        next unless id_data.is_a?(Hash)

        identifier_id = "#{entity_id}/identifier/#{idx}"

        id_type = id_data['type'] || id_data['id_type']
        id_value = id_data['value'] || id_data['id_number']

        @session.run(
          'MERGE (i:Identifier {id: $id}) SET i.type = $type, i.value = $value, i.issue_date = $issue_date, i.expiry_date = $expiry_date',
          id: identifier_id, type: id_type, value: id_value, issue_date: id_data['issue_date'], expiry_date: id_data['expiry_date']
        )

        @session.run(
          'MATCH (e:Entity {id: $entity_id}), (i:Identifier {id: $identifier_id}) MERGE (e)-[:HAS_IDENTIFIER]->(i)',
          entity_id: entity_id, identifier_id: identifier_id
        )
        identifier_count += 1

        # Issuing country relationship
        country = id_data['country_code'] || id_data['issuing_country']
        next unless country.is_a?(String) && country.length == 2

        @session.run(
          'MATCH (i:Identifier {id: $identifier_id}), (c:Country {code: $code}) MERGE (i)-[:ISSUED_BY]->(c)',
          identifier_id: identifier_id, code: country.upcase
        )
      end

      # Create Entry for this entity (linking to authority)
      entry_id = "#{entity_id}/entry/#{source}"
      @session.run(
        'MERGE (e:Entry {id: $id}) SET e.status = $status, e.listed_date = $listed_date, e.measures = $measures',
        id: entry_id, status: 'active', listed_date: data['listed_date'], measures: data['measures']
      )

      @session.run(
        'MATCH (entry:Entry {id: $entry_id}), (entity:Entity {id: $entity_id}) MERGE (entry)-[:FOR_ENTITY]->(entity)',
        entry_id: entry_id, entity_id: entity_id
      )

      @session.run(
        'MATCH (entry:Entry {id: $entry_id}), (auth:Authority {code: $auth_code}) MERGE (entry)-[:LISTED_BY]->(auth)',
        entry_id: entry_id, auth_code: source
      )
      entry_count += 1
    rescue StandardError => e
      puts "  Error processing #{f}: #{e.message}"
    end

    # Import separate entry files if they exist
    if Dir.exist?(entries_dir)
      Dir.glob(File.join(entries_dir, '*.yaml')).each do |f|
        data = YAML.load_file(f)
        next unless data.is_a?(Hash) && data['id']

        entry_id = data['id']
        entity_id = data['entity_id']

        @session.run(
          'MERGE (e:Entry {id: $id}) SET e.status = $status, e.listed_date = $listed_date, e.delisted_date = $delisted_date, e.list_type = $list_type, e.measures = $measures',
          id: entry_id, status: data['status'] || 'active', listed_date: data['listed_date'], delisted_date: data['delisted_date'], list_type: data['list_type'], measures: data['measures']
        )

        if entity_id
          @session.run(
            'MATCH (entry:Entry {id: $entry_id}), (entity:Entity {id: $entity_id}) MERGE (entry)-[:FOR_ENTITY]->(entity)',
            entry_id: entry_id, entity_id: entity_id
          )
        end

        auth_code = data['authority'] || data['authority_code'] || source
        @session.run(
          'MATCH (entry:Entry {id: $entry_id}), (auth:Authority {code: $auth_code}) MERGE (entry)-[:LISTED_BY]->(auth)',
          entry_id: entry_id, auth_code: auth_code
        )
        entry_count += 1
      end
    end

    puts "  Entities: #{entity_count}"
    puts "  Names: #{name_count}"
    puts "  Addresses: #{address_count}"
    puts "  Identifiers: #{identifier_count}"
    puts "  Entries: #{entry_count}"

    @stats[:nodes]['Entity'] = (@stats[:nodes]['Entity'] || 0) + entity_count
    @stats[:nodes]['Name'] = (@stats[:nodes]['Name'] || 0) + name_count
    @stats[:nodes]['Address'] = (@stats[:nodes]['Address'] || 0) + address_count
    @stats[:nodes]['Identifier'] = (@stats[:nodes]['Identifier'] || 0) + identifier_count
    @stats[:nodes]['Entry'] = (@stats[:nodes]['Entry'] || 0) + entry_count
  end

  def validate_data
    puts "\n=== Validation ==="

    validations = [
      ['Entities without names', 'MATCH (e:Entity) WHERE NOT (e)-[:HAS_NAME]->() RETURN count(e)'],
      ['Entries without entities', 'MATCH (e:Entry) WHERE NOT (e)-[:FOR_ENTITY]->() RETURN count(e)'],
      ['Entries without authorities', 'MATCH (e:Entry) WHERE NOT (e)-[:LISTED_BY]->() RETURN count(e)'],
      ['Orphaned names', 'MATCH (n:Name) WHERE NOT (n)<-[:HAS_NAME]-() RETURN count(n)'],
      ['Addresses without countries', 'MATCH (a:Address) WHERE NOT (a)-[:IN_COUNTRY]->() RETURN count(a)']
    ]

    all_passed = true
    validations.each do |name, query|
      result = @session.run(query)
      count = result.first[:count]
      status = count.zero? ? '✓' : '✗'
      puts "  #{status} #{name}: #{count}"
      all_passed = false if count.positive?
    end

    puts "\n#{all_passed ? '✓ All validations passed' : '✗ Some validations failed'}"
  end

  def print_stats
    puts "\n=== Final Statistics ==="

    puts 'Nodes:'
    result = @session.run('MATCH (n) RETURN labels(n)[0] as label, count(n) as count ORDER BY count DESC')
    result.each { |r| puts "  #{r[:label]}: #{r[:count]}" }

    puts "\nRelationships:"
    result = @session.run('MATCH ()-[r]->() RETURN type(r) as type, count(r) as count ORDER BY count DESC')
    result.each { |r| puts "  #{r[:type]}: #{r[:count]}" }
  end

  def type_to_label(type)
    case type.to_s.downcase
    when 'person' then 'Person'
    when 'organization' then 'Organization'
    when 'vessel' then 'Vessel'
    when 'aircraft' then 'Aircraft'
    else 'Entity'
    end
  end

  def extract_primary_name(names)
    return nil unless names.is_a?(Array) && names.any?

    primary = names.find do |n|
      if n.is_a?(Hash)
        if n['english'].is_a?(Hash)
          n['english']['is_primary'] || n['is_primary']
        else
          n['is_primary']
        end
      end
    end

    name_obj = primary || names.first

    if name_obj.is_a?(Hash)
      if name_obj['english'].is_a?(Hash)
        name_obj['english']['full_name']
      else
        name_obj['english'] || name_obj['full_name'] || name_obj['name']
      end
    elsif name_obj.is_a?(String)
      name_obj
    end
  end

  def load_iso_countries
    # Common ISO 3166-1 alpha-2 country codes
    {
      'AF' => 'Afghanistan', 'AL' => 'Albania', 'DZ' => 'Algeria', 'AR' => 'Argentina',
      'AU' => 'Australia', 'AT' => 'Austria', 'AZ' => 'Azerbaijan', 'BH' => 'Bahrain',
      'BD' => 'Bangladesh', 'BY' => 'Belarus', 'BE' => 'Belgium', 'BO' => 'Bolivia',
      'BA' => 'Bosnia and Herzegovina', 'BR' => 'Brazil', 'BG' => 'Bulgaria',
      'CA' => 'Canada', 'CL' => 'Chile', 'CN' => 'China', 'CO' => 'Colombia',
      'HR' => 'Croatia', 'CU' => 'Cuba', 'CY' => 'Cyprus', 'CZ' => 'Czech Republic',
      'DK' => 'Denmark', 'DO' => 'Dominican Republic', 'EC' => 'Ecuador', 'EG' => 'Egypt',
      'EE' => 'Estonia', 'FI' => 'Finland', 'FR' => 'France', 'GE' => 'Georgia',
      'DE' => 'Germany', 'GR' => 'Greece', 'GT' => 'Guatemala', 'HN' => 'Honduras',
      'HK' => 'Hong Kong', 'HU' => 'Hungary', 'IS' => 'Iceland', 'IN' => 'India',
      'ID' => 'Indonesia', 'IR' => 'Iran', 'IQ' => 'Iraq', 'IE' => 'Ireland',
      'IL' => 'Israel', 'IT' => 'Italy', 'JM' => 'Jamaica', 'JP' => 'Japan',
      'JO' => 'Jordan', 'KZ' => 'Kazakhstan', 'KE' => 'Kenya', 'KR' => 'South Korea',
      'KP' => 'North Korea', 'KW' => 'Kuwait', 'KG' => 'Kyrgyzstan', 'LV' => 'Latvia',
      'LB' => 'Lebanon', 'LY' => 'Libya', 'LT' => 'Lithuania', 'LU' => 'Luxembourg',
      'MY' => 'Malaysia', 'MT' => 'Malta', 'MX' => 'Mexico', 'MD' => 'Moldova',
      'ME' => 'Montenegro', 'MA' => 'Morocco', 'MM' => 'Myanmar', 'NL' => 'Netherlands',
      'NZ' => 'New Zealand', 'NI' => 'Nicaragua', 'NG' => 'Nigeria', 'NO' => 'Norway',
      'OM' => 'Oman', 'PK' => 'Pakistan', 'PS' => 'Palestine', 'PA' => 'Panama',
      'PY' => 'Paraguay', 'PE' => 'Peru', 'PH' => 'Philippines', 'PL' => 'Poland',
      'PT' => 'Portugal', 'PR' => 'Puerto Rico', 'QA' => 'Qatar', 'RO' => 'Romania',
      'RU' => 'Russia', 'SA' => 'Saudi Arabia', 'RS' => 'Serbia', 'SG' => 'Singapore',
      'SK' => 'Slovakia', 'SI' => 'Slovenia', 'ZA' => 'South Africa', 'ES' => 'Spain',
      'SD' => 'Sudan', 'SE' => 'Sweden', 'CH' => 'Switzerland', 'SY' => 'Syria',
      'TW' => 'Taiwan', 'TJ' => 'Tajikistan', 'TH' => 'Thailand', 'TN' => 'Tunisia',
      'TR' => 'Turkey', 'TM' => 'Turkmenistan', 'UA' => 'Ukraine', 'AE' => 'United Arab Emirates',
      'GB' => 'United Kingdom', 'US' => 'United States', 'UY' => 'Uruguay',
      'UZ' => 'Uzbekistan', 'VE' => 'Venezuela', 'VN' => 'Vietnam', 'YE' => 'Yemen',
      'ZW' => 'Zimbabwe', 'EU' => 'European Union', 'UN' => 'United Nations',
      'INT' => 'International', 'WB' => 'World Bank'
    }
  end
end

# Run the importer
if __FILE__ == $PROGRAM_NAME
  importer = FullNeo4jImporter.new
  importer.run
end
