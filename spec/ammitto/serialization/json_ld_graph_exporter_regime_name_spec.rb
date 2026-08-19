# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'ammitto/serialization/json_ld_graph_exporter'

# The entry's regime reference carried an @id and nothing else, so a
# consumer wanting a label had either to fetch the regime node or invent
# one from the identifier. The site invents one, and 158 of the 178
# published regimes read worse for it.
RSpec.describe Ammitto::Serialization::JsonLdGraphExporter do
  let(:output_dir) { Dir.mktmpdir('ammitto_regime_name') }
  let(:exporter) do
    described_class.new(output_dir: output_dir,
                        context_url: 'https://www.ammitto.org/ontology/context.jsonld')
  end

  after { FileUtils.rm_rf(output_dir) }

  def add_entry(regime)
    exporter.add_node(
      entity: { '@id' => 'https://www.ammitto.org/entity/un/e1',
                '@type' => 'PersonEntity' },
      entry: { '@id' => 'https://www.ammitto.org/entry/un/consolidated/e1',
               '@type' => 'SanctionEntry', 'regime' => regime },
      source: :un
    )
  end

  def reference
    exporter.entries.values.first['regime']
  end

  it 'carries the regime name beside the reference' do
    add_entry('code' => '1533', 'name' => "1533 (Democratic People's " \
                                          'Republic of the Congo)')

    expect(reference).to eq(
      '@id' => 'https://www.ammitto.org/regime/1533',
      'name' => "1533 (Democratic People's Republic of the Congo)"
    )
  end

  it 'still points at the regime node' do
    add_entry('code' => 'AU_AFGHANISTAN', 'name' => 'Afghanistan')

    expect(reference['@id']).to eq(exporter.regimes.values.first['@id'])
  end

  it 'omits the name rather than emitting a null when the source has none' do
    # A key holding null is worse than an absent key: a consumer testing
    # for presence gets a truthy answer and renders nothing.
    add_entry('code' => 'RUSSIA')

    expect(reference).to eq('@id' => 'https://www.ammitto.org/regime/russia')
    expect(reference).not_to have_key('name')
  end

  # The search index reads the SAME entry hash, after the graph exporter
  # has mutated it: harmonize_command.rb calls add_node then
  # search_indexer.add on one object. So stripping the name off the
  # reference also blinded the facet builder, whose `name` field fell back
  # to code.upcase for every regime published — AL_QAIDA where the source
  # says Al-Qaida. The search-index spec's own fixtures already carried a
  # name on the reference; nothing produced one.
  it 'leaves the search index a regime name to put in its facet' do
    require 'ammitto/serialization/search_index_exporter'
    indexer = Ammitto::Serialization::SearchIndexExporter.new
    entity = { '@id' => 'https://www.ammitto.org/entity/un/e1',
               '@type' => 'PersonEntity',
               'names' => [{ 'fullName' => 'Someone' }] }
    entry = { '@id' => 'https://www.ammitto.org/entry/un/consolidated/e1',
              '@type' => 'SanctionEntry',
              'regime' => { 'code' => 'AL_QAIDA', 'name' => 'Al-Qaida' } }

    exporter.add_node(entity: entity, entry: entry, source: :un)
    indexer.add(entity, entry)

    expect(indexer.facets[:regimes]['al_qaida'][:name]).to eq('Al-Qaida')
  end

  it 'leaves the regime node itself unchanged' do
    add_entry('code' => 'AL_QAIDA', 'name' => 'Al-Qaida',
              'description' => 'x')

    node = exporter.regimes.values.first
    expect(node).to include('@type' => 'SanctionRegime', 'name' => 'Al-Qaida',
                            'code' => 'AL_QAIDA', 'description' => 'x')
  end
end
