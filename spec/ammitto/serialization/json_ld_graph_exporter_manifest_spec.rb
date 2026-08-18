# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'tmpdir'
require 'ammitto/serialization/json_ld_graph_exporter'

# The catalogue's whole value is that a consumer can trust it. A listing
# that names a file which was never written is worse than no listing,
# because it turns a guessable 404 into a documented one.
RSpec.describe Ammitto::Serialization::JsonLdGraphExporter do
  around do |example|
    Dir.mktmpdir do |dir|
      @output_dir = dir
      example.run
    end
  end

  attr_reader :output_dir

  let(:exporter) do
    described_class.new(output_dir: output_dir, combine: combine)
  end
  let(:combine) { true }

  def manifest
    JSON.parse(File.read(File.join(output_dir, 'index.jsonld')))
  end

  def named(name)
    manifest['entries'].find { |e| e['name'] == name }
  end

  def add_entry(ref, source: :eu)
    entity = {
      '@id' => "https://www.ammitto.org/entity/#{source}/#{ref}",
      '@type' => 'PersonEntity',
      'names' => [{ 'fullName' => "Person #{ref}" }]
    }
    entry = {
      '@id' => "https://www.ammitto.org/entry/#{source}/#{ref}",
      '@type' => 'SanctionEntry',
      'referenceNumber' => ref
    }
    exporter.add_node(entity: entity, entry: entry, source: source)
  end

  # Mirrors the CLI's order: the graph exporter runs, then the caller
  # writes the per-source aggregates, the search index and the ontology,
  # and only then is the catalogue built. Building it earlier would omit
  # the three artefacts written last.
  before do
    add_entry('E-1')
    exporter.export
    FileUtils.mkdir_p(File.join(output_dir, 'sources'))
    File.write(File.join(output_dir, 'sources', 'eu.jsonld'), '{}')
    File.write(File.join(output_dir, 'search-index.json'), '[]')
    exporter.export_manifest
  end

  it 'writes a catalogue at the root of the published tree' do
    expect(File.exist?(File.join(output_dir, 'index.jsonld'))).to be(true)
    expect(manifest['@type']).to eq('Index')
    expect(manifest['slice']).to eq('catalogue')
  end

  it 'names the full dataset in both serialisations' do
    expect(named('all.jsonld')).to include('mediaType' => 'application/ld+json')
    expect(named('all.ttl')).to include('mediaType' => 'text/turtle')
  end

  it 'reports each dataset size, since one of them is very large' do
    # The two serialisations of the same graph differ by an order of
    # magnitude on the wire, because the host compresses one and not the
    # other. A consumer choosing between them should not have to start
    # the download to find that out.
    sizes = manifest['entries'].filter_map { |e| e['bytes'] }
    expect(sizes).to all(be > 0)
    expect(named('all.jsonld')['bytes']).to eq(
      File.size(File.join(output_dir, 'all.jsonld'))
    )
  end

  it 'lists the per-source aggregates that were written' do
    sources = named('sources')

    expect(sources['members']).to include('eu.jsonld')
  end

  # node/ has no files of its own: only node/entity and node/entry, each
  # with its own index. Judging a collection by its direct files alone
  # dropped the whole node API from the catalogue.
  it 'lists a collection whose content is entirely in subdirectories' do
    node = named('node')

    expect(node).not_to be_nil, 'node/ must appear in the catalogue'
    expect(node['collections']).to include('entity', 'entry')
  end

  it 'points a collection at its own index where one exists' do
    expect(named('by-authority')['index']).to eq('by-authority/index.jsonld')
  end

  # The failure this guards against: a source that fails its health gate
  # produces no aggregate, and a hardcoded catalogue would still name it.
  it 'never names a file that was not written' do
    urls = manifest['entries'].map { |e| e['url'] }
    urls.reject { |u| Dir.exist?(File.join(output_dir, u)) }.each do |u|
      expect(File.exist?(File.join(output_dir, u))).to be(true), "catalogued #{u}, which does not exist"
    end

    member_paths = manifest['entries'].flat_map do |e|
      (e['members'] || []).map { |m| File.join(e['url'], m) } +
        (e['collections'] || []).map { |c| File.join(e['url'], c) }
    end

    member_paths.each do |rel|
      expect(File.exist?(File.join(output_dir, rel))).to be(true), "catalogued #{rel}, which does not exist"
    end
  end

  it 'omits the aggregated files when they were not produced' do
    # `--combine` is optional; without it there is no all.jsonld to name.
    other = Dir.mktmpdir
    exp = described_class.new(output_dir: other, combine: false)
    exp.add_node(
      entity: { '@id' => 'https://www.ammitto.org/entity/eu/E-2',
                '@type' => 'PersonEntity',
                'names' => [{ 'fullName' => 'Person E-2' }] },
      entry: { '@id' => 'https://www.ammitto.org/entry/eu/E-2',
               '@type' => 'SanctionEntry' },
      source: :eu
    )
    exp.export
    exp.export_manifest

    names = JSON.parse(File.read(File.join(other, 'index.jsonld')))['entries']
                .map { |e| e['name'] }

    expect(names).not_to include('all.jsonld')
    expect(names).not_to include('all.ttl')
  ensure
    FileUtils.remove_entry(other) if other
  end
end
