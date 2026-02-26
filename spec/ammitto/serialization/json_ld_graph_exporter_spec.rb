# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'tmpdir'
require 'ammitto/serialization/json_ld_graph_exporter'
require 'ammitto/serialization/turtle_exporter'

RSpec.describe Ammitto::Serialization::JsonLdGraphExporter do
  let(:output_dir) { Dir.mktmpdir('ammitto_test') }
  let(:context_url) { 'https://www.ammitto.org/ontology/context.jsonld' }
  let(:exporter) { described_class.new(output_dir: output_dir, context_url: context_url) }

  after do
    FileUtils.rm_rf(output_dir)
  end

  describe '#add_node' do
    it 'stores entity and entry' do
      entity = {
        '@id' => 'https://www.ammitto.org/entity/un/KPi.066',
        '@type' => 'PersonEntity',
        'entityType' => 'person'
      }

      entry = {
        '@id' => 'https://www.ammitto.org/entry/un/KPi.066',
        '@type' => 'SanctionEntry',
        'entityId' => 'https://www.ammitto.org/entity/un/KPi.066',
        'authority' => { 'name' => 'UN', 'countryCode' => 'UN' },
        'regime' => { 'code' => 'DPRK', 'name' => 'DPRK' },
        'status' => 'active'
      }

      exporter.add_node(entity: entity, entry: entry, source: :un)

      expect(exporter.entities).to have_key('https://www.ammitto.org/entity/un/KPi.066')
      expect(exporter.entries).to have_key('https://www.ammitto.org/entry/un/KPi.066')
    end

    it 'extracts and deduplicates authorities' do
      entity = { '@id' => 'https://www.ammitto.org/entity/un/test1', '@type' => 'PersonEntity' }
      entry = {
        '@id' => 'https://www.ammitto.org/entry/un/test1',
        'authority' => { 'name' => 'United Nations', 'countryCode' => 'UN' }
      }

      exporter.add_node(entity: entity, entry: entry, source: :un)

      expect(exporter.authorities).to have_key('un')
      expect(exporter.authorities['un']['name']).to eq('United Nations')
      expect(entry['authority']).to eq({ '@id' => 'https://www.ammitto.org/authority/un' })
    end

    it 'extracts and deduplicates regimes' do
      entity = { '@id' => 'https://www.ammitto.org/entity/un/test1', '@type' => 'PersonEntity' }
      entry = {
        '@id' => 'https://www.ammitto.org/entry/un/test1',
        'regime' => { 'code' => 'DPRK', 'name' => 'Democratic People\'s Republic of Korea' }
      }

      exporter.add_node(entity: entity, entry: entry, source: :un)

      expect(exporter.regimes).to have_key('dprk')
      expect(exporter.regimes['dprk']['name']).to eq('Democratic People\'s Republic of Korea')
      expect(entry['regime']).to eq({ '@id' => 'https://www.ammitto.org/regime/dprk' })
    end

    it 'extracts and deduplicates legal instruments' do
      entity = { '@id' => 'https://www.ammitto.org/entity/un/test1', '@type' => 'PersonEntity' }
      entry = {
        '@id' => 'https://www.ammitto.org/entry/un/test1',
        'legalBases' => [
          { 'identifier' => 'UNSCR 1718', 'title' => 'UN Security Council Resolution 1718' }
        ]
      }

      exporter.add_node(entity: entity, entry: entry, source: :un)

      expect(exporter.instruments.length).to eq(1)
      expect(entry['legalBases'].first).to have_key('@id')
      expect(entry['legalBases'].first['@id']).to include('instrument/un/')
    end
  end

  describe '#export' do
    before do
      entity = {
        '@id' => 'https://www.ammitto.org/entity/un/KPi.066',
        '@type' => 'PersonEntity',
        'entityType' => 'person'
      }
      entry = {
        '@id' => 'https://www.ammitto.org/entry/un/KPi.066',
        '@type' => 'SanctionEntry',
        'entityId' => 'https://www.ammitto.org/entity/un/KPi.066',
        'authority' => { 'name' => 'UN', 'countryCode' => 'UN' },
        'regime' => { 'code' => 'DPRK', 'name' => 'DPRK' },
        'status' => 'active'
      }
      exporter.add_node(entity: entity, entry: entry, source: :un)
    end

    it 'creates directory structure' do
      exporter.export

      expect(Dir.exist?(File.join(output_dir, 'node', 'entity', 'un'))).to be true
      expect(Dir.exist?(File.join(output_dir, 'node', 'entry', 'un'))).to be true
      expect(Dir.exist?(File.join(output_dir, 'node', 'authority'))).to be true
      expect(Dir.exist?(File.join(output_dir, 'node', 'regime'))).to be true
    end

    it 'exports individual entity node files' do
      exporter.export

      entity_file = File.join(output_dir, 'node', 'entity', 'un', 'KPi.066.jsonld')
      expect(File.exist?(entity_file)).to be true

      data = JSON.parse(File.read(entity_file))
      expect(data['@id']).to eq('https://www.ammitto.org/entity/un/KPi.066')
      expect(data['@type']).to eq('PersonEntity')
    end

    it 'exports individual entry node files with @id references' do
      exporter.export

      entry_file = File.join(output_dir, 'node', 'entry', 'un', 'KPi.066.jsonld')
      expect(File.exist?(entry_file)).to be true

      data = JSON.parse(File.read(entry_file))
      expect(data['@id']).to eq('https://www.ammitto.org/entry/un/KPi.066')
      expect(data['authority']).to eq({ '@id' => 'https://www.ammitto.org/authority/un' })
      expect(data['regime']).to eq({ '@id' => 'https://www.ammitto.org/regime/dprk' })
    end

    it 'exports authority node files' do
      exporter.export

      auth_file = File.join(output_dir, 'node', 'authority', 'un.jsonld')
      expect(File.exist?(auth_file)).to be true

      data = JSON.parse(File.read(auth_file))
      expect(data['@id']).to eq('https://www.ammitto.org/authority/un')
      expect(data['@type']).to eq('Authority')
    end

    it 'exports regime node files' do
      exporter.export

      regime_file = File.join(output_dir, 'node', 'regime', 'dprk.jsonld')
      expect(File.exist?(regime_file)).to be true

      data = JSON.parse(File.read(regime_file))
      expect(data['@id']).to eq('https://www.ammitto.org/regime/dprk')
      expect(data['@type']).to eq('SanctionRegime')
    end

    it 'exports index files for each node type' do
      exporter.export

      expect(File.exist?(File.join(output_dir, 'node', 'entity', 'index.jsonld'))).to be true
      expect(File.exist?(File.join(output_dir, 'node', 'entry', 'index.jsonld'))).to be true
      expect(File.exist?(File.join(output_dir, 'node', 'authority', 'index.jsonld'))).to be true
      expect(File.exist?(File.join(output_dir, 'node', 'regime', 'index.jsonld'))).to be true
      expect(File.exist?(File.join(output_dir, 'node', 'instrument', 'index.jsonld'))).to be true
    end

    it 'exports all.jsonld aggregated file' do
      exporter.export

      all_file = File.join(output_dir, 'all.jsonld')
      expect(File.exist?(all_file)).to be true

      data = JSON.parse(File.read(all_file))
      expect(data['@graph']).to be_an(Array)
      expect(data['@graph'].length).to be >= 4 # authority, regime, entity, entry
    end

    it 'exports all.ttl Turtle file' do
      exporter.export

      ttl_file = File.join(output_dir, 'all.ttl')
      expect(File.exist?(ttl_file)).to be true

      content = File.read(ttl_file)
      expect(content).to include('@prefix ammitto:')
    end

    it 'exports stats.json' do
      exporter.export

      stats_file = File.join(output_dir, 'stats.json')
      expect(File.exist?(stats_file)).to be true

      stats = JSON.parse(File.read(stats_file))
      expect(stats['total_entities']).to eq(1)
      expect(stats['total_entries']).to eq(1)
      expect(stats['sources']).to have_key('un')
    end

    it 'exports data slice directories' do
      exporter.export

      expect(Dir.exist?(File.join(output_dir, 'by-authority'))).to be true
      expect(Dir.exist?(File.join(output_dir, 'by-regime'))).to be true
      expect(Dir.exist?(File.join(output_dir, 'by-status'))).to be true
      expect(Dir.exist?(File.join(output_dir, 'by-type'))).to be true
    end

    it 'exports by-authority index files with @id references' do
      exporter.export

      # Check master index
      master_index = File.join(output_dir, 'by-authority', 'index.jsonld')
      expect(File.exist?(master_index)).to be true

      master = JSON.parse(File.read(master_index))
      expect(master['slice']).to eq('by-authority')
      expect(master['available']).to include('https://www.ammitto.org/authority/un')

      # Check authority-specific index
      un_index = File.join(output_dir, 'by-authority', 'un.jsonld')
      expect(File.exist?(un_index)).to be true

      un_data = JSON.parse(File.read(un_index))
      expect(un_data['entries']).to be_an(Array)
      expect(un_data['entries'].first).to have_key('@id')
    end

    it 'exports by-regime index files with @id references' do
      exporter.export

      # Check master index
      master_index = File.join(output_dir, 'by-regime', 'index.jsonld')
      expect(File.exist?(master_index)).to be true

      # Check regime-specific index
      dprk_index = File.join(output_dir, 'by-regime', 'dprk.jsonld')
      expect(File.exist?(dprk_index)).to be true

      dprk_data = JSON.parse(File.read(dprk_index))
      expect(dprk_data['entries']).to be_an(Array)
      expect(dprk_data['entries'].first).to have_key('@id')
    end

    it 'exports by-status index files with @id references' do
      exporter.export

      # Check master index
      master_index = File.join(output_dir, 'by-status', 'index.jsonld')
      expect(File.exist?(master_index)).to be true

      # Check status-specific index
      active_index = File.join(output_dir, 'by-status', 'active.jsonld')
      expect(File.exist?(active_index)).to be true

      active_data = JSON.parse(File.read(active_index))
      expect(active_data['status']).to eq('active')
      expect(active_data['entries']).to be_an(Array)
    end
  end
end
