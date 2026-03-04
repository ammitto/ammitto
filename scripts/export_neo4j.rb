#!/usr/bin/env ruby
# frozen_string_literal: true

# Export Ammitto Knowledge Graph to Neo4j CSV format
#
# Usage:
#   ruby scripts/export_neo4j.rb [base_dir] [output_dir]
#
# Example:
#   ruby scripts/export_neo4j.rb /Users/src/ammitto ./neo4j_import

# Add lib to load path
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'ammitto/serialization/neo4j_exporter'

# Base directory containing data-* repositories
default_base_dir = File.expand_path('..', File.dirname(__dir__))
base_dir = ARGV[0] || default_base_dir
output_dir = ARGV[1] || File.join(base_dir, 'neo4j_import')

puts '=== Exporting Knowledge Graph to Neo4j CSV ==='
puts "Base directory: #{base_dir}"
puts "Output directory: #{output_dir}"
puts ''

exporter = Ammitto::Serialization::Neo4jExporter.new

# Find all data-* directories
data_dirs = Dir.glob(File.join(base_dir, 'data-*')).select { |d| File.directory?(d) }

puts "Found #{data_dirs.size} data directories"

data_dirs.each do |data_dir|
  processed_dir = File.join(data_dir, 'processed')
  next unless File.directory?(processed_dir)

  # Extract source code from directory name
  source_code = File.basename(data_dir).gsub(/^data-/, '')

  # Handle special cases
  source_code = case source_code
                when 'eu_vessels' then 'eu-vessels'
                when 'un_vessels' then 'un-vessels'
                else source_code
                end

  puts "  Processing #{source_code}..."
  exporter.add_source(processed_dir, source_code)
end

puts ''
puts '=== Exporting CSV Files ==='
exporter.export(output_dir)

puts ''
puts '=== Next Steps ==='
puts '1. Copy CSV files to Neo4j import directory'
puts '2. Run the import script: neo4j_import.cypher'
puts ''
