# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/serialization/json_ld_serializer'
require 'ammitto/serialization/json_ld_graph_exporter'
require 'ammitto/serialization/search_index_exporter'
require 'fileutils'
require 'tmpdir'

# The search index's `authority` column is what public consumers filter on,
# and Ammitto has no authority concept coarser than the source that issued
# the listing: BaseTransformer builds every authority as
# Authority.find(source_code), Authority::REGISTRY is keyed by source code,
# and Schema::Validator checks authority['id'] against that registry.
#
# Neither exporter is exercised against a real registered authority
# anywhere else in the suite, and only their combination is what harmonize
# actually runs, so these examples drive the exact component order of
# HarmonizeCommand#ingest_results -- JsonLdGraphExporter#add_node first,
# then SearchIndexExporter#add on the same, now-rewritten entry hash.
RSpec.describe 'Authority identity through the harmonize pipeline' do
  let(:output_dir) { Dir.mktmpdir('ammitto_authority_identity') }
  let(:serializer) { Ammitto::Serialization::JsonLdSerializer.new }
  let(:graph) do
    Ammitto::Serialization::JsonLdGraphExporter.new(output_dir: output_dir)
  end
  let(:index) { Ammitto::Serialization::SearchIndexExporter.new }

  after { FileUtils.rm_rf(output_dir) }

  # Mirrors HarmonizeCommand#ingest_results for one entity/entry pair
  def ingest(source)
    entity = {
      '@id' => "https://www.ammitto.org/entity/#{source}/t1",
      'entityType' => 'person',
      'names' => [{ 'fullName' => "Subject #{source}", 'isPrimary' => true }]
    }
    entry = serializer.serialize_entry(
      Ammitto::SanctionEntry.new(
        id: "https://www.ammitto.org/entry/#{source}/t1",
        authority: Ammitto::Authority.find(source),
        status: 'active'
      )
    )

    graph.add_node(entity: entity, entry: entry, source: source)
    index.add(entity, entry)
  end

  # uk declares countryCode GB, so a country-keyed authority publishes 'gb'
  # for it. eu_vessels and un_vessels declare EU and UN, so a country-keyed
  # authority hides them inside their parent's bucket.
  %w[uk eu_vessels un_vessels].each do |source|
    it "indexes #{source} under its own authority code" do
      ingest(source)

      expect(index.entities.first[:authority]).to eq(source)
    end
  end

  it 'gives every registered source a code its own validator accepts' do
    validator = Ammitto::Schema::Validator.new
    Ammitto::Authority::REGISTRY.each_key { |source| ingest(source) }

    codes = index.entities.map { |row| row[:authority] }.uniq
    unknown = codes.reject do |code|
      validator.validate_sanction_entry('authority' => { 'id' => code })
               .grep(/Unknown authority/).empty?
    end

    expect(unknown).to be_empty
  end

  it 'counts a vessel source separately from its parent authority' do
    ingest('eu')
    ingest('eu_vessels')

    expect(index.facets[:authorities]).to include('eu' => 1, 'eu_vessels' => 1)
  end

  # AUTHORITY_NAMES already carries 'EU Vessels'; it was unreachable while
  # the code collapsed to 'eu'
  it 'names the vessel facet from AUTHORITY_NAMES' do
    ingest('eu_vessels')
    index.export(output_dir)

    facets = JSON.parse(
      File.read(File.join(output_dir, 'facets', 'authorities.json'))
    )['facets']

    expect(facets).to include(
      hash_including('code' => 'eu_vessels', 'name' => 'EU Vessels')
    )
  end

  it 'gives a vessel source its own authority node keyed by id' do
    ingest('eu')
    ingest('eu_vessels')
    graph.export

    node = File.join(output_dir, 'node', 'authority', 'eu_vessels.jsonld')
    expect(File.exist?(node)).to be true

    data = JSON.parse(File.read(node))
    expect(data['@id']).to eq('https://www.ammitto.org/authority/eu_vessels')
    expect(data['name']).to eq('EU Designated Vessels (via Denmark DMA)')
    # the declared country code survives the id-keyed node
    expect(data['countryCode']).to eq('EU')
  end

  it 'stops minting an authority node for a country that is not a source' do
    ingest('uk')
    graph.export

    dir = File.join(output_dir, 'node', 'authority')
    expect(File.exist?(File.join(dir, 'uk.jsonld'))).to be true
    expect(File.exist?(File.join(dir, 'gb.jsonld'))).to be false
  end
end
