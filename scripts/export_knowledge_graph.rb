#!/usr/bin/env ruby
# frozen_string_literal: true

# Export harmonized knowledge graph data from all data-* repositories
# Usage: ruby scripts/export_knowledge_graph.rb [base_dir] [output_dir]

# Add lib to load path
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'ammitto'
require 'ammitto/serialization/search_index_exporter'

# Base directory should be the parent of the ammitto gem directory
# which contains all data-* repositories
default_base_dir = File.expand_path('..', File.dirname(__dir__))
base_dir = ARGV[0] || default_base_dir
output_dir = ARGV[1] || File.join(base_dir, 'ammitto.github.io', 'public', 'api', 'v1')

puts '=== Exporting Knowledge Graph Data ==='
puts "Base directory: #{base_dir}"
puts "Output directory: #{output_dir}"
puts ''

exporter = Ammitto::Exporter::KnowledgeGraphExporter.new(base_dir, output_dir: output_dir)
results = exporter.export_all

puts '=== Export Results ==='
puts "Total entities: #{results[:total_entities]}"
puts "Total entries: #{results[:total_entries]}"
puts ''

puts '=== Sources ==='
results[:sources].each do |code, stats|
  puts "  #{code}: #{stats[:entities]} entities, #{stats[:entries]} entries"
end

if results[:errors].any?
  puts ''
  puts '=== Errors ==='
  results[:errors].each { |e| puts "  - #{e}" }
end

# Export search index
puts ''
puts '=== Exporting Search Index ==='

search_exporter = Ammitto::Serialization::SearchIndexExporter.new

# Load all data again for search index
Ammitto::Exporter::KnowledgeGraphExporter::DATA_SOURCES.each do |source_name|
  processed_dir = File.join(base_dir, source_name, 'processed')
  next unless File.directory?(processed_dir)

  entities_dir = File.join(processed_dir, 'entities')
  entries_dir = File.join(processed_dir, 'entries')
  next unless File.directory?(entities_dir) && File.directory?(entries_dir)

  begin
    loader = Ammitto::Data::KnowledgeGraphLoader.new(processed_dir)
    harmonized = loader.to_harmonized

    # Match entities with entries
    entries_by_entity = harmonized[:entries].group_by { |e| e['entity_id'] }

    harmonized[:entities].each do |entity|
      entity_entries = entries_by_entity[entity['id']] || []
      entity_entries.each do |entry|
        search_exporter.add(entity, entry)
      end
    end

    puts "  #{source_name}: #{harmonized[:entities].size} entities indexed"
  rescue StandardError => e
    puts "  #{source_name}: ERROR - #{e.message}"
  end
end

# Export search index
search_exporter.export(output_dir)
puts '  Search index exported'

puts ''
puts 'Export complete!'
