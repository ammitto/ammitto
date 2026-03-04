#!/usr/bin/env ruby
# frozen_string_literal: true

# Full pipeline: Import to Neo4j -> Validate -> Export JSON-LD
#
# Usage:
#   ruby scripts/run_full_pipeline.rb [--skip-import] [--skip-validation] [--skip-export]

require 'optparse'
require 'fileutils'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

options = {
  skip_import: false,
  skip_validation: false,
  skip_export: false,
  neo4j_container: 'ammitto-neo4j',
  clear: false
}

OptionParser.new do |opts|
  opts.banner = 'Usage: ruby scripts/run_full_pipeline.rb [options]'

  opts.on('--skip-import', 'Skip Neo4j import') { options[:skip_import] = true }
  opts.on('--skip-validation', 'Skip validation') { options[:skip_validation] = true }
  opts.on('--skip-export', 'Skip JSON-LD export') { options[:skip_export] = true }
  opts.on('--container=NAME', 'Neo4j container name') { |n| options[:neo4j_container] = n }
  opts.on('--clear', 'Clear existing Neo4j data') { options[:clear] = true }
end.parse!

require 'neo4j/driver'
require 'yaml'
require 'json'
require 'ammitto/ontology'
require 'ammitto/ontology/json_ld_context'

include Neo4j::Driver

class Pipeline
  CONTAINER = 'ammitto-neo4j'

  def initialize(options)
    @options = options
    @stats = {}
  end

  def run
    setup_data_symlinks unless Dir.exist?('../data-au')

    connect_neo4j

    import unless @options[:skip_import]
    validate unless @options[:skip_validation]
    export unless @options[:skip_export]

    disconnect_neo4j

    puts "\n=== Pipeline Complete ==="
  end

  private

  def setup_data_symlinks
    base = File.expand_path('..', __dir__)
    return unless Dir.exist?(File.join(base, 'ammitto'))

    Dir.glob(File.join(base, 'ammitto', 'data-*')).each do |dir|
      target = File.join(base, File.basename(dir))
      unless Dir.exist?(target)
        puts "Creating symlink: #{target} -> #{dir}"
        File.symlink(dir, target)
      end
    end
  end

  def connect_neo4j
    puts 'Connecting to Neo4j...'
    @driver = GraphDatabase.driver('bolt://localhost:7688', AuthTokens.basic('neo4j', 'password'))
    @session = @driver.session
    puts 'Connected'
  rescue StandardError => e
    puts 'ERROR: Could not connect to Neo4j. Is it running?'
    puts e.message
    exit 1
  end

  def disconnect_neo4j
    @session&.close
    @driver&.close
  end

  def import
    puts "\n=== Importing to Neo4j ==="
    system('bundle exec ruby scripts/import_neo4j_full.rb')
  end

  def validate
    puts "\n=== Validation ==="

    checks = [
      ['Entities without names', 'MATCH (e:Entity) WHERE NOT (e)-[:HAS_NAME]->() RETURN count(e)'],
      ['Entries without entities', 'MATCH (e:Entry) WHERE NOT (e)-[:FOR_ENTITY]->() RETURN count(e)'],
      ['Entries without authorities', 'MATCH (e:Entry) WHERE NOT (e)-[:LISTED_BY]->() RETURN count(e)'],
      ['Orphaned names', 'MATCH (n:Name) WHERE NOT (n)<-[:HAS_NAME]-() RETURN count(n)']
    ]

    all_passed = true
    checks.each do |name, query|
      result = @session.run(query)
      count = result.first[:count]
      status = count.zero? ? '✓' : '✗'
      puts "  #{status} #{name}: #{count}"
      all_passed = false if count.positive?
    end

    # Node counts
    puts "\nNode counts:"
    result = @session.run('MATCH (n) RETURN labels(n)[0] as type, count(n) as count ORDER BY count DESC')
    result.each { |r| puts "  #{r[:type]}: #{r[:count]}" }

    unless all_passed
      puts "\n✗ VALIDATION FAILED"
      exit 1
    end

    puts "\n✓ ALL VALIDATIONS PASSED"
  end

  def export
    puts "\n=== Exporting JSON-LD ==="
    system('bundle exec ruby scripts/export_json_ld.rb')
  end
end

Pipeline.new(options).run
