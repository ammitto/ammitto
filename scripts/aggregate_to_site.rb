#!/usr/bin/env ruby
# frozen_string_literal: true

# Aggregate all harmonized data from data-* directories to the site API
# Run from ammitto root: ruby scripts/aggregate_to_site.rb

require 'json'
require 'yaml'
require 'pathname'

# Paths
AMMITTO_ROOT = Pathname.new(__dir__).parent
SITE_DIR = AMMITTO_ROOT.parent / 'ammitto.github.io'
SITE_API_DIR = SITE_DIR / 'api' / 'v1'

# Source directories
DATA_DIRS = %w[
  data-au data-ca data-ch data-cn data-eu data-eu-vessels
  data-jp data-nz data-ru data-tr data-uk data-un
  data-un-vessels data-us data-wb
].freeze

def aggregate
  puts 'Aggregating harmonized data to site...'
  puts "Site API directory: #{SITE_API_DIR}"

  # Ensure target directory exists
  SITE_API_DIR.mkpath
  (SITE_API_DIR / 'sources').mkpath
  (SITE_API_DIR / 'facets').mkpath
  (SITE_API_DIR / 'ontology').mkpath

  # Copy ontology from first available source
  DATA_DIRS.each do |dir_name|
    data_dir = AMMITTO_ROOT.parent / dir_name
    source_ontology_dir = data_dir / 'api' / 'ontology'

    next unless source_ontology_dir.exist? && (source_ontology_dir / 'classes.jsonld').exist?

    puts "  Copying ontology from #{dir_name}..."
    FileUtils.cp_r(source_ontology_dir, SITE_API_DIR / 'ontology')
    break
  end
  all_search_entries = []
  source_stats = {}
  total_entities = 0
  total_entries = 0

  DATA_DIRS.each do |dir_name|
    data_dir = AMMITTO_ROOT.parent / dir_name
    api_dir = data_dir / 'api'

    unless api_dir.exist?
      puts "  Skipping #{dir_name}: no API directory"
      next
    end

    source_code = dir_name.sub('data-', '').gsub('-', '_')
    puts "  Processing #{dir_name} (#{source_code})..."

    # Read stats
    stats_file = api_dir / 'stats.json'
    if stats_file.exist?
      stats = JSON.parse(File.read(stats_file))
      entity_count = stats['total_entities'] || 0
      entry_count = stats['total_entries'] || 0

      source_stats[source_code] = {
        'entities' => entity_count,
        'entries' => entry_count
      }

      total_entities += entity_count
      total_entries += entry_count

      puts "    Entities: #{entity_count}, Entries: #{entry_count}"
    end

    # Read search index
    search_file = api_dir / 'search-index.json'
    if search_file.exist?
      search_data = JSON.parse(File.read(search_file))
      entries = search_data['entities'] || []
      all_search_entries.concat(entries)
      puts "    Search entries: #{entries.length}"
    end

    # Copy all.jsonld to sources directory
    all_jsonld = api_dir / 'all.jsonld'
    if all_jsonld.exist?
      dest = SITE_API_DIR / 'sources' / "#{source_code}.jsonld"
      FileUtils.cp(all_jsonld, dest)
      puts "    Copied all.jsonld to sources/#{source_code}.jsonld"
    end

    # Copy facets if they exist
    facets_dir = api_dir / 'facets'
    next unless facets_dir.exist?

    facets_dir.glob('*.json').each do |facet_file|
      dest = SITE_API_DIR / 'facets' / "#{source_code}_#{facet_file.basename}"
      FileUtils.cp(facet_file, dest)
    end
    puts '    Copied facets'
  end

  # Write combined search index
  combined_search = {
    'metadata' => {
      'generated' => Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
      'totalEntities' => all_search_entries.length,
      'sources' => source_stats.keys.length
    },
    'entities' => all_search_entries
  }

  search_path = SITE_API_DIR / 'search-index.json'
  File.write(search_path, JSON.generate(combined_search))
  puts "\nWrote combined search index: #{all_search_entries.length} entities"

  # Write combined stats
  combined_stats = {
    'generated_at' => Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
    'total_entities' => total_entities,
    'total_entries' => total_entries,
    'sources' => source_stats
  }

  stats_path = SITE_API_DIR / 'stats.json'
  File.write(stats_path, JSON.generate(combined_stats, indent: '  '))
  puts "Wrote combined stats: #{total_entities} entities, #{total_entries} entries"

  puts "\nAggregation complete!"
end

aggregate if __FILE__ == $PROGRAM_NAME
