#!/usr/bin/env ruby
# frozen_string_literal: true

# Coverage Report Generator
#
# Generates a detailed report comparing declared properties vs. actual Neo4j data.
# This report proves that 100% of declared properties are being exported.
#
# Output formats:
# - Console report (human readable)
# - JSON report (machine readable)
#
# Usage:
#   ruby scripts/generate_coverage_report.rb [--format json]

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'neo4j/driver'
require 'json'
require 'optparse'
require 'ammitto/ontology'

include Neo4j::Driver

class CoverageReportGenerator
  CLASSES_TO_CHECK = [
    { class: Ammitto::Ontology::Entities::PersonEntity, label: 'Person' },
    { class: Ammitto::Ontology::Entities::OrganizationEntity, label: 'Organization' },
    { class: Ammitto::Ontology::Entities::VesselEntity, label: 'Vessel' },
    { class: Ammitto::Ontology::Entities::AircraftEntity, label: 'Aircraft' },
    { class: Ammitto::Ontology::ValueObjects::NameVariant, label: 'Name' },
    { class: Ammitto::Ontology::ValueObjects::Address, label: 'Address' },
    { class: Ammitto::Ontology::ValueObjects::Identification, label: 'Identifier' },
    { class: Ammitto::Ontology::ValueObjects::BirthInfo, label: 'BirthInfo' },
    { class: Ammitto::Ontology::ValueObjects::ContactInfo, label: 'ContactInfo' }
  ].freeze

  def initialize(uri: 'bolt://localhost:7688', username: 'neo4j', password: 'password')
    @uri = uri
    @username = username
    @password = password
    @driver = nil
    @session = nil
    @report = {
      generated_at: Time.now.iso8601,
      classes: [],
      summary: {}
    }
  end

  def run
    connect
    generate_report
    disconnect
    @report
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

  def generate_report
    CLASSES_TO_CHECK.each do |config|
      check_class(config[:class], config[:label])
    end

    calculate_summary
  end

  def check_class(klass, label)
    declared_props = klass.all_neo4j_property_attributes.map(&:to_s)

    # Get actual properties from Neo4j
    existing_result = @session.run(
      "MATCH (n:#{label}) WITH n LIMIT 100 RETURN keys(n) as props"
    )

    # Collect all unique properties from sampled nodes
    existing_props = Set.new
    node_count = 0
    existing_result.each do |row|
      existing_props.merge(row[:props])
      node_count += 1
    end

    # Get total node count
    count_result = @session.run("MATCH (n:#{label}) RETURN count(n) as count")
    total_count = count_result.first[:count]

    # Calculate coverage
    missing_in_neo4j = declared_props - existing_props.to_a
    extra_in_neo4j = (existing_props.to_a - declared_props - ['id'])

    # Calculate property population rates
    population_rates = calculate_population_rates(label, declared_props, total_count)

    class_report = {
      class_name: klass.name,
      neo4j_label: label,
      total_nodes: total_count,
      sampled_nodes: node_count,
      declared_properties: declared_props.sort,
      existing_properties: existing_props.to_a.sort,
      missing_in_neo4j: missing_in_neo4j.sort,
      extra_in_neo4j: extra_in_neo4j.sort,
      population_rates: population_rates,
      coverage_percent: calculate_coverage_percent(declared_props, missing_in_neo4j)
    }

    @report[:classes] << class_report
  end

  def calculate_population_rates(label, properties, total_count)
    return {} if total_count.zero?

    rates = {}
    properties.each do |prop|
      result = @session.run(
        "MATCH (n:#{label}) WHERE n.#{prop} IS NOT NULL RETURN count(n) as count"
      )
      populated = result.first[:count]
      rates[prop] = {
        populated: populated,
        total: total_count,
        percent: (populated.to_f / total_count * 100).round(2)
      }
    end
    rates
  end

  def calculate_coverage_percent(declared, missing)
    return 100.0 if declared.empty?

    ((declared.size - missing.size).to_f / declared.size * 100).round(2)
  end

  def calculate_summary
    total_declared = @report[:classes].sum { |c| c[:declared_properties].size }
    total_missing = @report[:classes].sum { |c| c[:missing_in_neo4j].size }
    total_extra = @report[:classes].sum { |c| c[:extra_in_neo4j].size }

    @report[:summary] = {
      total_classes: @report[:classes].size,
      total_declared_properties: total_declared,
      total_missing_properties: total_missing,
      total_extra_properties: total_extra,
      overall_coverage_percent: calculate_coverage_percent(
        (1..total_declared).to_a,
        (1..total_missing).to_a
      ),
      all_classes_covered: @report[:classes].all? { |c| c[:missing_in_neo4j].empty? }
    }
  end
end

# Parse command line options
options = {
  uri: 'bolt://localhost:7688',
  username: 'neo4j',
  password: 'password',
  format: 'console'
}

OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"

  opts.on('-f', '--format FORMAT', 'Output format: console, json') do |format|
    options[:format] = format
  end

  opts.on('-u', '--uri URI', 'Neo4j URI') do |uri|
    options[:uri] = uri
  end

  opts.on('--username USER', 'Neo4j username') do |user|
    options[:username] = user
  end

  opts.on('--password PASS', 'Neo4j password') do |pass|
    options[:password] = pass
  end
end.parse!

# Generate report
generator = CoverageReportGenerator.new(
  uri: options[:uri],
  username: options[:username],
  password: options[:password]
)

report = generator.run

if options[:format] == 'json'
  puts JSON.pretty_generate(report)
else
  # Console output
  puts '=' * 70
  puts 'ONTOLOGY COVERAGE REPORT'
  puts '=' * 70
  puts "\nGenerated at: #{report[:generated_at]}"
  puts "\n#{'-' * 70}"

  report[:classes].each do |class_report|
    puts "\n#{class_report[:class_name]} (#{class_report[:neo4j_label]})"
    puts "  Nodes in Neo4j: #{class_report[:total_nodes]}"
    puts "  Declared properties: #{class_report[:declared_properties].join(', ')}"

    if class_report[:missing_in_neo4j].any?
      puts "  ❌ Missing in Neo4j: #{class_report[:missing_in_neo4j].join(', ')}"
    else
      puts '  ✓ All declared properties exist'
    end

    puts "  ⚠️  Extra in Neo4j: #{class_report[:extra_in_neo4j].join(', ')}" if class_report[:extra_in_neo4j].any?

    puts "  Coverage: #{class_report[:coverage_percent]}%"
  end

  puts "\n#{'=' * 70}"
  puts 'SUMMARY'
  puts '=' * 70
  puts "\nTotal classes: #{report[:summary][:total_classes]}"
  puts "Total declared properties: #{report[:summary][:total_declared_properties]}"
  puts "Missing properties: #{report[:summary][:total_missing_properties]}"
  puts "Extra properties: #{report[:summary][:total_extra_properties]}"
  puts "Overall coverage: #{report[:summary][:overall_coverage_percent]}%"

  if report[:summary][:all_classes_covered]
    puts "\n✓ ALL CLASSES HAVE 100% COVERAGE"
  else
    puts "\n✗ SOME CLASSES HAVE MISSING PROPERTIES"
  end
end
