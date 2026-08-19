# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'tmpdir'
require 'ammitto/serialization/json_ld_graph_exporter'

# Regime codes reach the graph exactly as the source states them, and
# Canada states them bilingually: "CA_China / Chine". Interpolated into
# an IRI that produced .../regime/ca_china / chine -- a Turtle IRIREF
# cannot hold a space, and every consumer that splits an IRI on "/"
# reads the French half as the identifier.
RSpec.describe Ammitto::Serialization::JsonLdGraphExporter do
  let(:output_dir) { Dir.mktmpdir('ammitto_regime_iri') }
  let(:exporter) do
    described_class.new(output_dir: output_dir,
                        context_url: 'https://www.ammitto.org/ontology/context.jsonld')
  end

  after { FileUtils.rm_rf(output_dir) }

  def add_entry(ref, regime_code)
    exporter.add_node(
      entity: { '@id' => "https://www.ammitto.org/entity/ca/#{ref}",
                '@type' => 'PersonEntity' },
      entry: { '@id' => "https://www.ammitto.org/entry/ca/consolidated/#{ref}",
               '@type' => 'SanctionEntry',
               'regime' => { 'code' => regime_code, 'name' => regime_code } },
      source: :ca
    )
  end

  it 'mints a regime IRI a Turtle IRIREF can hold' do
    add_entry('e1', 'CA_China / Chine')

    id = exporter.regimes.values.first['@id']

    expect(id).to eq('https://www.ammitto.org/regime/ca_china-chine')
  end

  it 'keys the regime by the same slug the IRI ends in' do
    # The key becomes node/regime/<key>.jsonld. A key of "ca_china /
    # chine" wrote the node inside a directory named "ca_china " and
    # left it unreachable at the @id the node itself advertises.
    add_entry('e1', 'CA_China / Chine')

    key = exporter.regimes.keys.first
    id = exporter.regimes.values.first['@id']

    expect(key).to eq('ca_china-chine')
    expect(id).to end_with("/#{key}")
  end

  it 'leaves the entry pointing at the sanitized regime' do
    add_entry('e1', 'CA_China / Chine')

    ref = exporter.entries.values.first.dig('regime', '@id')

    expect(ref).to eq('https://www.ammitto.org/regime/ca_china-chine')
    expect(ref.split('/').last).to eq('ca_china-chine')
  end

  it 'merges codes that differ only in trailing whitespace' do
    # ca published both; they are one regime and were two nodes.
    add_entry('e1', 'CA_Moldova')
    add_entry('e2', 'CA_Moldova ')

    expect(exporter.regimes.keys).to eq(['ca_moldova'])
  end

  it 'advertises an index @id the node filename answers to' do
    # The key is the node filename and the index rebuilds the IRI from
    # it, so the slug has to survive a second sanitizing pass. Canada's
    # longest code truncates to exactly the limit and left a hyphen at
    # the end; re-sanitizing dropped it and the index pointed at a file
    # that was never written.
    add_entry('e1', 'CA_Justice for victims of corrupt foreign officials ' \
                    'regulations (JVCFOR) / Reglement relatif a la justice')

    key = exporter.regimes.keys.first
    id = exporter.regimes.values.first['@id']

    expect(Ammitto::Utils::IriSanitizer.regime_iri(key)).to eq(id)
    expect(id).to end_with("/#{key}")
  end

  it 'keeps a clean code byte-identical' do
    add_entry('e1', 'BELARUS-EO14038')

    expect(exporter.regimes.keys).to eq(['belarus-eo14038'])
    expect(exporter.regimes.values.first['@id'])
      .to eq('https://www.ammitto.org/regime/belarus-eo14038')
  end
end
