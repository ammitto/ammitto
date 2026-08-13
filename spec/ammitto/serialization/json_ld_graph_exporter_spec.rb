# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'tmpdir'
require 'yaml'
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

    # An authority's identity is its id. Authority::REGISTRY is keyed by
    # source code and Schema::Validator checks authority['id'] against it,
    # so keying the node on the coarser countryCode both merged distinct
    # authorities and minted IRIs that validator rejects ('gb' is not a
    # registry key; 'uk' is).
    it 'keys the authority node on its id rather than its country code' do
      entity = { '@id' => 'https://www.ammitto.org/entity/uk/test1' }
      entry = {
        '@id' => 'https://www.ammitto.org/entry/uk/test1',
        'authority' => {
          'id' => 'uk',
          'name' => 'United Kingdom (OFSI)',
          'countryCode' => 'GB'
        }
      }

      exporter.add_node(entity: entity, entry: entry, source: :uk)

      expect(exporter.authorities).to have_key('uk')
      expect(exporter.authorities).not_to have_key('gb')
      expect(entry['authority'])
        .to eq({ '@id' => 'https://www.ammitto.org/authority/uk' })
    end

    it 'keeps the declared country code on the id-keyed authority node' do
      entity = { '@id' => 'https://www.ammitto.org/entity/uk/test1' }
      entry = {
        '@id' => 'https://www.ammitto.org/entry/uk/test1',
        'authority' => {
          'id' => 'uk',
          'name' => 'United Kingdom (OFSI)',
          'countryCode' => 'GB'
        }
      }

      exporter.add_node(entity: entity, entry: entry, source: :uk)

      expect(exporter.authorities['uk']['countryCode']).to eq('GB')
    end

    # eu and eu_vessels are separate registry entries that both declare
    # countryCode EU. Keyed by country they collapsed into one node whose
    # name was decided by ingestion order.
    it 'keeps authorities sharing a country code distinct' do
      exporter.add_node(
        entity: { '@id' => 'https://www.ammitto.org/entity/eu/test1' },
        entry: {
          '@id' => 'https://www.ammitto.org/entry/eu/test1',
          'authority' => {
            'id' => 'eu', 'name' => 'European Union', 'countryCode' => 'EU'
          }
        },
        source: :eu
      )
      exporter.add_node(
        entity: { '@id' => 'https://www.ammitto.org/entity/eu_vessels/test1' },
        entry: {
          '@id' => 'https://www.ammitto.org/entry/eu_vessels/test1',
          'authority' => {
            'id' => 'eu_vessels',
            'name' => 'EU Designated Vessels (via Denmark DMA)',
            'countryCode' => 'EU'
          }
        },
        source: :eu_vessels
      )

      expect(exporter.authorities.keys).to contain_exactly('eu', 'eu_vessels')
      expect(exporter.authorities['eu']['name']).to eq('European Union')
      expect(exporter.authorities['eu_vessels']['name'])
        .to eq('EU Designated Vessels (via Denmark DMA)')
    end

    it 'still falls back to the country code when there is no id' do
      entity = { '@id' => 'https://www.ammitto.org/entity/un/test1' }
      entry = {
        '@id' => 'https://www.ammitto.org/entry/un/test1',
        'authority' => { 'name' => 'United Nations', 'countryCode' => 'UN' }
      }

      exporter.add_node(entity: entity, entry: entry, source: :un)

      expect(exporter.authorities).to have_key('un')
      expect(exporter.authorities['un']['countryCode']).to eq('UN')
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
        '@id' => 'https://www.ammitto.org/entry/un/consolidated-list/KPi.066',
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
      expect(Dir.exist?(File.join(output_dir, 'node', 'entry', 'un', 'consolidated-list'))).to be true
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

      entry_file = File.join(output_dir, 'node', 'entry', 'un', 'consolidated-list', 'KPi.066.jsonld')
      expect(File.exist?(entry_file)).to be true

      data = JSON.parse(File.read(entry_file))
      expect(data['@id']).to eq('https://www.ammitto.org/entry/un/consolidated-list/KPi.066')
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
      expect(File.exist?(File.join(output_dir, 'node', 'legal-instrument', 'index.jsonld'))).to be true
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

  describe '#extract_instruments' do
    let(:instrument_iri) { 'https://www.ammitto.org/legal_instrument/cn/afsl' }
    let(:citation) do
      {
        'legalInstrumentId' => instrument_iri,
        'articles' => ['Article 4'],
        'citationType' => 'legal_basis'
      }
    end

    def rewrite(entry)
      exporter.send(:extract_instruments, entry, 'cn')
      entry
    end

    it 'rewrites citations under the camelCase term the context declares' do
      entry = rewrite({ 'legalCitations' => [citation] })

      expect(entry['legalCitations']).to eq(
        [{
          '@type' => 'LegalCitation',
          'legalInstrumentId' => 'https://www.ammitto.org/legal-instrument/cn/afsl',
          'articles' => ['Article 4'],
          'citationType' => 'legal_basis'
        }]
      )
    end

    it 'leaves no snake_case citation key behind' do
      entry = rewrite({ 'legalCitations' => [citation] })

      expect(entry).not_to have_key('legal_citations')
    end

    it 'still accepts snake_case input from an older cache' do
      entry = rewrite(
        { 'legal_citations' => [{ 'legal_instrument_id' => instrument_iri, 'citation_type' => 'reference' }] }
      )

      expect(entry['legalCitations'].first).to include('citationType' => 'reference')
      expect(entry).not_to have_key('legal_citations')
    end

    it 'registers the cited instrument as a node of its own' do
      rewrite({ 'legalCitations' => [citation] })

      expect(exporter.send(:instance_variable_get, :@instruments).keys)
        .to include('https://www.ammitto.org/legal-instrument/cn/afsl')
    end

    it 'carries through every citation field the serializer emitted' do
      entry = rewrite(
        { 'legalCitations' => [citation.merge(
          '@id' => 'https://www.ammitto.org/citation/cn/1',
          '@type' => 'LegalCitation',
          'sections' => ['Section 2'],
          'paragraphs' => ['Paragraph 1'],
          'context' => 'Primary authority',
          'quotedText' => [{ 'value' => 'quoted', 'lang' => 'en' }]
        )] }
      )

      expect(entry['legalCitations'].first).to include(
        '@id' => 'https://www.ammitto.org/citation/cn/1',
        'sections' => ['Section 2'],
        'paragraphs' => ['Paragraph 1'],
        'context' => 'Primary authority',
        'quotedText' => [{ 'value' => 'quoted', 'lang' => 'en' }]
      )
    end

    it 'prefers the canonical spelling when a citation carries both' do
      %i[legacy_first canonical_first].each do |order|
        pair = { 'citation_type' => 'legacy', 'citationType' => 'canonical' }
        entry = rewrite(
          { 'legalCitations' => [
            { 'legalInstrumentId' => instrument_iri }
              .merge(order == :legacy_first ? pair : pair.to_a.reverse.to_h)
          ] }
        )

        expect(entry['legalCitations'].first['citationType']).to eq('canonical')
      end
    end
  end

  describe 'supplement loading' do
    let(:supplements_root) { Dir.mktmpdir('ammitto_supplements') }

    after do
      FileUtils.rm_rf(supplements_root)
    end

    def write_yaml(path, data)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, YAML.dump(data))
      path
    end

    def write_document_types(repo, id, name)
      write_yaml(
        File.join(supplements_root, repo, 'supporting', 'document-types.yml'),
        'document_types' => [{ 'id' => id, 'name' => { 'en' => name } }]
      )
      File.join(supplements_root, repo, 'supporting')
    end

    def english_name(node)
      node['name'].find { |n| n['lang'] == 'en' }['value']
    end

    it 'combines every directory into populated page slices' do
      us_supporting = File.join(supplements_root, 'data-us', 'supporting')
      cn_supporting = File.join(supplements_root, 'data-cn', 'supporting')
      us_instruments = File.join(supplements_root, 'data-us',
                                 'legal-instruments')
      cn_instruments = File.join(supplements_root, 'data-cn',
                                 'legal-instruments')

      write_yaml(
        File.join(us_supporting, 'document-types.yml'),
        'document_types' => [
          { 'id' => 'us/designation', 'name' => { 'en' => 'Designation' } }
        ]
      )
      write_yaml(
        File.join(us_supporting, 'organizations.yml'),
        'organizations' => [{ 'id' => 'us/ofac', 'name' => { 'en' => 'OFAC' } }]
      )
      write_yaml(
        File.join(cn_supporting, 'document-types.yml'),
        'document_types' => [{ 'id' => 'cn/act', 'name' => { 'en' => 'Act' } }]
      )
      write_yaml(
        File.join(cn_supporting, 'organizations.yml'),
        'organizations' => [
          { 'id' => 'cn/ministry', 'name' => { 'en' => 'Ministry' } }
        ]
      )
      write_yaml(File.join(us_instruments, 'law.yml'),
                 'id' => 'us/law', 'type' => 'us/designation',
                 'title' => 'US law')
      write_yaml(File.join(cn_instruments, 'law.yml'),
                 'id' => 'cn/law', 'type' => 'cn/act', 'title' => 'CN law')

      merged = described_class.new(
        output_dir: output_dir,
        context_url: context_url,
        combine: false,
        supporting_dir: [us_supporting, cn_supporting],
        instruments_dir: [us_instruments, cn_instruments]
      )

      expect(merged.document_types.keys).to contain_exactly(
        'https://www.ammitto.org/document-type/us/designation',
        'https://www.ammitto.org/document-type/cn/act'
      )
      expect(merged.organizations.keys).to contain_exactly(
        'https://www.ammitto.org/organization/us/ofac',
        'https://www.ammitto.org/organization/cn/ministry'
      )
      expect(merged.loaded_instruments.keys)
        .to contain_exactly('us/law', 'cn/law')

      merged.add_node(
        entity: { '@id' => 'https://www.ammitto.org/entity/cn/1' },
        entry: {
          '@id' => 'https://www.ammitto.org/entry/cn/list/1',
          'announcement' => {
            'documentType' => 'cn/act',
            'documentId' => 'CN-1',
            'publisher' => 'cn/ministry'
          },
          'legalCitations' => [{
            'legalInstrumentId' =>
              'https://www.ammitto.org/legal_instrument/cn/law'
          }]
        },
        source: :cn
      )
      merged.export

      document_slice = JSON.parse(File.read(File.join(
                                              output_dir, 'by-document-type',
                                              'cn', 'act.jsonld'
                                            )))
      organization_slice = JSON.parse(File.read(File.join(
                                                  output_dir,
                                                  'by-organization', 'cn',
                                                  'ministry.jsonld'
                                                )))

      expect(document_slice['announcements'])
        .to match([a_hash_including('documentId' => 'CN-1')])
      expect(document_slice['legalInstruments'])
        .to match([a_hash_including('identifier' => 'law')])
      expect(organization_slice['published'])
        .to match([a_hash_including('documentId' => 'CN-1')])
    end

    it 'keeps the first claim on an identifier and reports the duplicate' do
      first = write_document_types('data-cn', 'cn/act', 'Claimed first')
      second = write_document_types('data-jp', 'cn/act', 'Claimed second')

      merged = nil
      expect do
        merged = described_class.new(
          output_dir: output_dir, context_url: context_url,
          supporting_dir: [first, second]
        )
      end.to output(%r{Document type .*cn/act.* is already defined})
        .to_stderr

      expect(merged.document_types.size).to eq(1)
      expect(english_name(merged.document_types.values.first))
        .to eq('Claimed first')
    end

    it 'still accepts a single directory as a bare string' do
      supporting = write_document_types('data-cn', 'cn/act', 'Act')

      single = described_class.new(
        output_dir: output_dir, context_url: context_url,
        supporting_dir: supporting
      )

      expect(single.document_types.keys)
        .to eq(['https://www.ammitto.org/document-type/cn/act'])
    end
  end
end
