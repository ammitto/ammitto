# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/cli'
require 'ammitto/cli/harmonize_command'
require 'tmpdir'

RSpec.describe Ammitto::Cmd::HarmonizeCommand do
  def person(source, suffix = 'one', names_only: false)
    Ammitto::PersonEntity.new(
      id: "https://www.ammitto.org/entity/#{source}/#{suffix}", entity_type: 'person',
      names: [Ammitto::NameVariant.new(full_name: 'Alexander Petrov')],
      birth_info: names_only ? [] : [Ammitto::BirthInfo.new(date: Date.new(1970, 5, 12))]
    )
  end

  def run_publication(root, names_only: false, duplicate: false)
    sources = %w[un eu]
    sources.each do |source|
      directory = File.join(root, "data-#{source}", 'processed')
      FileUtils.mkdir_p(directory)
      File.write(File.join(directory, 'one.yaml'), { 'source' => source }.to_yaml)
      File.write(File.join(directory, 'two.yaml'), { 'source' => source }.to_yaml) if duplicate && source == 'un'
    end
    options = { sources_dir: root, output_dir: File.join(root, 'api'), combine: true,
                report: File.join(root, 'report.json') }
    command = described_class.new(options, sources)
    serializer = Ammitto::Serialization::JsonLdSerializer.new
    allow(command).to receive(:transform_data) do |source, _data, **_kwargs|
      entity = person(source, names_only: names_only)
      entry = Ammitto::SanctionEntry.new(
        id: "https://www.ammitto.org/entry/#{source}/list/one", entity_id: entity.id,
        authority: Ammitto::Authority.new(id: "https://www.ammitto.org/authority/#{source}", name: source.to_s),
        status: 'active'
      )
      { entity: serializer.serialize_entity(entity), entry: serializer.serialize_entry(entry) }
    end
    command.run
    options
  end

  it 'publishes identical symmetric links in source, node, combined JSON-LD and Turtle while retaining all entries and search IDs' do
    Dir.mktmpdir('matching-publication') do |root|
      options = run_publication(root, duplicate: true)
      output = options[:output_dir]
      aggregate = JSON.parse(File.read(File.join(output, 'all.jsonld')))['@graph']
      %w[un eu].each do |source|
        iri = "https://www.ammitto.org/entity/#{source}/one"
        other = "https://www.ammitto.org/entity/#{source == 'un' ? 'eu' : 'un'}/one"
        source_nodes = JSON.parse(File.read(File.join(output, 'sources', "#{source}.jsonld")))['@graph']
        node = JSON.parse(File.read(File.join(output, 'node/entity', source, 'one.jsonld')))
        expect(source_nodes.find { |item| item['@id'] == iri }['sameAs']).to eq([other])
        expect(aggregate.find { |item| item['@id'] == iri }['sameAs']).to eq([other])
        expect(node['sameAs']).to eq([other])
        expect(aggregate).to include(a_hash_including('@id' => "https://www.ammitto.org/entry/#{source}/list/one", 'entityId' => iri))
        [File.join(output, 'all.ttl'), File.join(output, 'sources', "#{source}.ttl")].each do |path|
          statements = RDF::Turtle::Reader.new(File.read(path)).each_statement.to_a
          expect(statements).to include(RDF::Statement.new(RDF::URI(iri), RDF::OWL.sameAs, RDF::URI(other)))
        end
        shard = JSON.parse(File.read(File.join(output, 'search-index', "#{source}.json")))
        expect(shard.to_s).to include(iri)
      end
      report = JSON.parse(File.read(options[:report]))
      expect(report['gates_passed']).to be(true)
      expect(report['entity_matching']['published_pairs']).to eq(1)
      expect(report['entity_matching']['matches'].first['evidence']).to eq('full_birth_date_and_name')
    end
  end

  it 'validates a failure report when no sources reach matching' do
    Dir.mktmpdir('matching-failed') do |root|
      options = { sources_dir: root, output_dir: File.join(root, 'api'), report: File.join(root, 'report.json') }
      command = described_class.new(options, ['eu'])
      expect { command.run }.to raise_error(Thor::Error, /No input directory/)
      report = JSON.parse(File.read(options[:report]))
      expect(report['entity_matching']).to be_nil
      validator = Ammitto::Validation::OutputValidator.new(output_dir: options[:output_dir])
      expect(validator.validate_files([options[:report]], report: options[:report])).to be_valid
    end
  end

  it 'persists name-only review candidates in a validated report even when there are zero published matches' do
    Dir.mktmpdir('matching-review') do |root|
      options = run_publication(root, names_only: true)
      report = JSON.parse(File.read(options[:report]))
      expect(report['entity_matching']['published_pairs']).to eq(0)
      expect(report['entity_matching']['review_candidates'].first['reason']).to eq('name_similarity_requires_review')
      expect(report['gates_passed']).to be(true)
    end
  end
end
