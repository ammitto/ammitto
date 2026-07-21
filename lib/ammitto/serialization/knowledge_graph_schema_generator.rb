# frozen_string_literal: true

# Knowledge Graph Schema Generator
#
# This class reads the knowledge_graph_schema.yaml and generates:
# 1. Neo4j import Cypher script
# 2. Validation queries
# 3. CSV header definitions
#
# The schema is the SINGLE SOURCE OF TRUTH for the knowledge graph structure.
# All Neo4j exports, imports, and validations MUST be generated from this schema.

require 'yaml'
require 'erb'

module Ammitto
  module Serialization
    class KnowledgeGraphSchemaGenerator
      attr_reader :schema

      def initialize(schema_path = nil)
        schema_path ||= File.join(File.dirname(__FILE__), 'knowledge_graph_schema.yaml')
        @schema = YAML.load_file(schema_path)
      end

      # Get all node definitions
      def nodes
        @schema['nodes'] || {}
      end

      # Get all relationship definitions
      def relationships
        @schema['relationships'] || []
      end

      # Get CSV file definitions
      def csv_files
        @schema['csv_files'] || {}
      end

      # Get validation rules
      def validations
        @schema['validations'] || []
      end

      # Generate Neo4j CREATE CONSTRAINT statements
      def generate_constraints
        constraints = []

        nodes.each_value do |node_def|
          node_def['properties'].each do |prop_name, prop_def|
            if prop_def['unique']
              label = node_def['label']
              constraints << "CREATE CONSTRAINT IF NOT EXISTS FOR (n:#{label}) REQUIRE n.#{prop_name} IS UNIQUE;"
            end
          end
        end

        constraints
      end

      # Generate Neo4j CREATE INDEX statements
      def generate_indexes
        indexes = []

        nodes.each_value do |node_def|
          node_def['properties'].each do |prop_name, prop_def|
            if prop_def['index'] && !prop_def['unique']
              label = node_def['label']
              indexes << "CREATE INDEX IF NOT EXISTS FOR (n:#{label}) ON (n.#{prop_name});"
            end
          end
        end

        indexes
      end

      # Generate LOAD CSV statements for node imports
      def generate_node_imports
        imports = []

        csv_files['nodes'].each do |csv_def|
          csv_name = csv_def['name']
          node_label = csv_def['node']
          header = csv_def['header']

          node_def = nodes[node_label]
          next unless node_def

          # Find the unique key for this node
          unique_key = find_unique_key(node_def)

          # Generate SET clause for properties
          set_clauses = []
          header.each_with_index do |col, idx|
            next if col == unique_key # Skip the key used in MERGE

            set_clauses << "n.#{col} = row[#{idx}]"
          end

          imports << {
            file: "#{csv_name}.csv",
            label: node_def['label'],
            unique_key: unique_key,
            set_clause: set_clauses.join(', '),
            header: header
          }
        end

        imports
      end

      # Generate LOAD CSV statements for relationship imports
      def generate_relationship_imports
        imports = []

        csv_files['relationships'].each do |csv_def|
          csv_name = csv_def['name']
          rel_name = csv_def['relationship']
          header = csv_def['header']

          rel_def = relationships.find { |r| r['name'] == rel_name }
          next unless rel_def

          imports << {
            file: "#{csv_name}.csv",
            type: rel_def['type'],
            from_label: nodes[rel_def['from']]&.dig('label'),
            to_label: nodes[rel_def['to']]&.dig('label'),
            from_key: header[0],
            to_key: header[1]
          }
        end

        imports
      end

      # Generate the full Neo4j import script
      def generate_import_script
        script = <<~CYPHER
          // ============================================================
          // Neo4j Import Script for Ammitto Knowledge Graph
          // AUTO-GENERATED from knowledge_graph_schema.yaml
          // DO NOT EDIT MANUALLY - regenerate using:
          //   ruby scripts/generate_neo4j_import.rb
          // ============================================================

        CYPHER

        # Add constraints
        script += "// ============================================================\n"
        script += "// STEP 1: Create Constraints\n"
        script += "// ============================================================\n"
        generate_constraints.each { |c| script += "#{c}\n" }
        script += "\n"

        # Add indexes
        script += "// ============================================================\n"
        script += "// STEP 2: Create Indexes\n"
        script += "// ============================================================\n"
        generate_indexes.each { |i| script += "#{i}\n" }
        script += "\n"

        # Add node imports
        script += "// ============================================================\n"
        script += "// STEP 3: Import Nodes\n"
        script += "// ============================================================\n"
        generate_node_imports.each do |import|
          script += "// Import #{import[:label]} nodes\n"
          script += "LOAD CSV FROM 'file:///#{import[:file]}' AS row\n"
          script += "MERGE (n:#{import[:label]} {#{import[:unique_key]}: row[0]})\n"
          script += "SET #{import[:set_clause]};\n\n" unless import[:set_clause].empty?
        end

        # Add relationship imports
        script += "// ============================================================\n"
        script += "// STEP 4: Import Relationships\n"
        script += "// ============================================================\n"
        generate_relationship_imports.each do |import|
          script += "// Create #{import[:type]} relationships\n"
          script += "LOAD CSV FROM 'file:///#{import[:file]}' AS row\n"
          script += "MATCH (from:#{import[:from_label]} {#{map_key(import[:from_key])}: row[0]})\n"
          script += "MATCH (to:#{import[:to_label]} {#{map_key(import[:to_key])}: row[1]})\n"
          script += "MERGE (from)-[:#{import[:type]}]->(to);\n\n"
        end

        # Add validation
        script += "// ============================================================\n"
        script += "// STEP 5: Validation\n"
        script += "// ============================================================\n"
        script += generate_validation_section

        script
      end

      # Generate validation section
      def generate_validation_section
        section = "// Node counts\n"
        section += "MATCH (n)\n"
        section += "RETURN labels(n)[0] as node_type, count(n) as count\n"
        section += "ORDER BY count DESC;\n\n"

        section += "// Relationship counts\n"
        section += "MATCH ()-[r]->()\n"
        section += "RETURN type(r) as relationship_type, count(r) as count\n"
        section += "ORDER BY count DESC;\n\n"

        section += "// Data quality checks\n"
        validations.each do |val|
          section += "// #{val['description']}\n"
          section += "#{val['query']}\n\n"
        end

        section
      end

      # Generate validation script content
      def generate_validation_script
        <<~BASH
          #!/bin/bash
          # Neo4j Data Validation Script
          # AUTO-GENERATED from knowledge_graph_schema.yaml
          # DO NOT EDIT MANUALLY

          set -e

          CONTAINER=${1:-ammitto-neo4j}

          cypher() {
              docker exec $CONTAINER cypher-shell -u neo4j -p password "$1"
          }

          echo "=== Neo4j Data Validation ==="
          echo ""

          echo "=== Node Counts ==="
          cypher "MATCH (n) RETURN labels(n)[0] as node_type, count(n) as count ORDER BY count DESC;"

          echo ""
          echo "=== Relationship Counts ==="
          cypher "MATCH ()-[r]->() RETURN type(r) as relationship_type, count(r) as count ORDER BY count DESC;"

          echo ""
          echo "=== Data Quality Checks ==="

          #{validations.map { |v| generate_validation_check(v) }.join("\n")}

          echo ""
          echo "✅ PASSED: All data quality checks passed!"
        BASH
      end

      private

      def find_unique_key(node_def)
        node_def['properties'].each do |prop_name, prop_def|
          return prop_name if prop_def['unique']
        end
        'id' # default
      end

      def map_key(key)
        # Map CSV column names to node property names
        key_mappings = {
          'entry_id' => 'id',
          'entity_id' => 'id',
          'authority_code' => 'code',
          'announcement_id' => 'id',
          'regime_code' => 'code',
          'name_id' => 'id',
          'address_id' => 'id',
          'identifier_id' => 'id',
          'country_code' => 'code'
        }
        key_mappings[key] || key
      end

      def generate_validation_check(val)
        <<~BASH
          echo "Checking: #{val['description']}"
          COUNT=$(cypher "#{val['query'].strip}" | tail -1)
          echo "  Count: $COUNT (expected: #{val['expected']})"
          if [ "$COUNT" -gt #{val['expected']} ]; then
              echo "❌ FAILED: #{val['description']}"
              exit 1
          fi

        BASH
      end
    end
  end
end
