#!/usr/bin/env ruby
# frozen_string_literal: true

# Direct Neo4j Importer
#
# This script imports data directly to Neo4j using Ruby, without CSV files.
# The ontology classes ARE the schema.
#
# Usage:
#   ruby scripts/import_neo4j_direct.rb [options]
#
# Options:
#   --clear    Clear existing data before import
#   --source   Only import specific source (e.g., 'cn')

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'ammitto/serialization/neo4j_direct_importer'
require 'optparse'

options = {
  clear: false,
  source: nil,
  container: 'ammitto-neo4j',
  username: 'neo4j',
  password: 'password'
}

OptionParser.new do |opts|
  opts.banner = 'Usage: ruby scripts/import_neo4j_direct.rb [options]'

  opts.on('--clear', 'Clear existing data before import') do
    options[:clear] = true
  end

  opts.on('--source=SOURCE', 'Only import specific source') do |s|
    options[:source] = s
  end

  opts.on('--container=NAME', 'Neo4j Docker container name') do |c|
    options[:container] = c
  end

  opts.on('--username=USER', 'Neo4j username') do |u|
    options[:username] = u
  end

  opts.on('--password=PASS', 'Neo4j password') do |p|
    options[:password] = p
  end

  opts.on('--help', 'Show this help') do
    puts opts
    exit
  end
end.parse!

# Set clear option via environment
ENV['CLEAR_NEO4J'] = 'true' if options[:clear]

# Determine base directory - check for data-* directories
base_dir = File.expand_path('..', __dir__)

# Check if we have data-* directories
if Dir.exist?(File.join(base_dir, 'data-au'))
  # Data is in separate repositories at same level
  base_dir = File.expand_path('..', base_dir)
end

puts '=== Direct Neo4j Import ==='
puts "Base directory: #{base_dir}"
puts "Container: #{options[:container]}"
puts "Clear existing: #{options[:clear]}"
puts

importer = Ammitto::Serialization::Neo4jDirectImporter.new(
  container: options[:container],
  username: options[:username],
  password: options[:password]
)

importer.import_from_directory(base_dir)
importer.print_stats
