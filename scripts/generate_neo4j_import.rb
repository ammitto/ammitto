#!/usr/bin/env ruby
# frozen_string_literal: true

# Generate Neo4j import script from knowledge graph schema
#
# Usage:
#   ruby scripts/generate_neo4j_import.rb [output_dir]
#
# This script reads the knowledge_graph_schema.yaml and generates:
# - neo4j_import.cypher - Neo4j import script
# - validate_neo4j.sh - Validation script

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'ammitto/serialization/knowledge_graph_schema_generator'
require 'fileutils'

output_dir = ARGV[0] || File.expand_path('../../neo4j_import', __dir__)
FileUtils.mkdir_p(output_dir)

generator = Ammitto::Serialization::KnowledgeGraphSchemaGenerator.new

# Generate Neo4j import script
import_script = generator.generate_import_script
File.write(File.join(output_dir, 'neo4j_import.cypher'), import_script)
puts "Generated: #{output_dir}/neo4j_import.cypher"

# Generate validation script
validation_script = generator.generate_validation_script
File.write(File.join(output_dir, 'validate_neo4j.sh'), validation_script)
FileUtils.chmod(0o755, File.join(output_dir, 'validate_neo4j.sh'))
puts "Generated: #{output_dir}/validate_neo4j.sh"

# Print summary
puts ''
puts 'Schema summary:'
puts "  Nodes: #{generator.nodes.size}"
puts "  Relationships: #{generator.relationships.size}"
puts "  Validations: #{generator.validations.size}"
puts ''
puts 'CSV files:'
generator.csv_files['nodes'].each do |csv|
  puts "  - #{csv['name']}.csv (#{csv['node']})"
end
generator.csv_files['relationships'].each do |csv|
  puts "  - #{csv['name']}.csv (#{csv['relationship']})"
end
