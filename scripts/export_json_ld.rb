#!/usr/bin/env ruby
# frozen_string_literal: true

# Export JSON-LD from Neo4j Knowledge Graph
#
# Generates JSON-LD documents for website consumption.

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'neo4j/driver'
require 'json'
require 'fileutils'
require 'ammitto/ontology/json_ld_context'

include Neo4j::Driver

class JsonLdExporter
  def initialize(uri: 'bolt://localhost:7688', username: 'neo4j', password: 'password')
    @uri = uri
    @username = username
    @password = password
    @driver = nil
    @session = nil
  end

  def run(output_dir: '/Users/mulgogi/src/ammitto/data/ontology/json-ld')
    connect

    # Ensure output directory
    FileUtils.mkdir_p(output_dir)

    puts "Exporting to #{output_dir}"

    # Export entities
    export_entities(output_dir)

    # Export authorities
    export_authorities(output_dir)

    # Export context
    export_context(output_dir)

    disconnect
    puts 'Export complete!'
  end

  private

  def connect
    @driver = GraphDatabase.driver(@uri, AuthTokens.basic(@username, @password))
    @session = @driver.session
  end

  def disconnect
    @session&.close
    @driver&.close
  end

  def json_context
    @json_context ||= Ammitto::Ontology::JsonLdContext.generate
  end

  def export_entities(output_dir)
    entities_dir = File.join(output_dir, 'entities')
    FileUtils.mkdir_p(entities_dir)

    puts 'Exporting entities...'

    count = 0
    result = @session.run('MATCH (e:Entity) RETURN e.id as id, e.source as source, e.type as type, e.primary_name as name, e.remarks as remarks')

    result.each do |row|
      entity_id = row[:id]
      entity_type = row[:type]

      # Get names
      names_result = @session.run(
        'MATCH (e:Entity {id: $id})-[:HAS_NAME]->(n:Name) RETURN n.full_name as name, n.is_primary as is_primary',
        id: entity_id
      )
      names = names_result.map { |n| { 'name' => n[:name], 'is_primary' => n[:is_primary] } }

      # Get addresses
      addr_result = @session.run(
        'MATCH (e:Entity {id: $id})-[:HAS_ADDRESS]->(a:Address) RETURN a.city as city, a.country_code as country',
        id: entity_id
      )
      addresses = addr_result.map { |a| { 'city' => a[:city], 'country' => a[:country] } }

      # Build JSON-LD doc
      doc = {
        '@context' => json_context,
        '@id' => entity_id,
        '@type' => map_type(entity_type),
        'source' => row[:source],
        'names' => names,
        'addresses' => addresses
      }

      doc['remarks'] = row[:remarks] if row[:remarks]

      # Write to file
      filename = "#{entity_id.gsub(/[^a-zA-Z0-9\-_]/, '_')[0..60]}.jsonld"
      File.write(File.join(entities_dir, filename), JSON.pretty_generate(doc))

      count += 1
      print '.' if (count % 1000).zero?
    end

    puts " Exported #{count} entities"
  end

  def export_authorities(output_dir)
    auth_dir = File.join(output_dir, 'authorities')
    FileUtils.mkdir_p(auth_dir)

    puts 'Exporting authorities...'

    result = @session.run('MATCH (a:Authority) RETURN a.code as code, a.name as name, a.country_code as country')

    count = 0
    result.each do |row|
      doc = {
        '@context' => json_context,
        '@id' => "https://www.ammitto.org/authority/#{row[:code]}",
        '@type' => 'Authority',
        'code' => row[:code],
        'name' => row[:name],
        'country' => row[:country]
      }

      File.write(File.join(auth_dir, "#{row[:code]}.jsonld"), JSON.pretty_generate(doc))
      count += 1
    end

    puts " Exported #{count} authorities"
  end

  def export_context(output_dir)
    doc = {
      '@context' => json_context
    }

    File.write(File.join(output_dir, 'context.jsonld'), JSON.pretty_generate(doc))
    puts 'Exported context'
  end

  def map_type(type)
    case type
    when 'person' then 'Person'
    when 'organization' then 'Organization'
    when 'vessel' then 'Vessel'
    else 'Entity'
    end
  end
end

# Run
exporter = JsonLdExporter.new
exporter.run
