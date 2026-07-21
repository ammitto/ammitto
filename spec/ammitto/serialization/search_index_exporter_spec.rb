# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'tmpdir'
require 'ammitto/serialization/search_index_exporter'

RSpec.describe Ammitto::Serialization::SearchIndexExporter do
  let(:output_dir) { Dir.mktmpdir('ammitto_search_test') }
  let(:exporter) { described_class.new }

  after do
    FileUtils.rm_rf(output_dir)
  end

  describe '#add' do
    it 'adds entity to search index' do
      entity = {
        '@id' => 'https://www.ammitto.org/entity/un/KPi.066',
        '@type' => 'PersonEntity',
        'entityType' => 'person',
        'names' => [
          { 'fullName' => 'KIM, Jong Un', 'isPrimary' => true },
          { 'fullName' => '金正恩' }
        ]
      }

      entry = {
        '@id' => 'https://www.ammitto.org/entry/un/KPi.066',
        'authority' => { '@id' => 'https://www.ammitto.org/authority/un' },
        'regime' => { '@id' => 'https://www.ammitto.org/regime/dprk', 'name' => 'DPRK' },
        'status' => 'active'
      }

      exporter.add(entity, entry)

      expect(exporter.entities.length).to eq(1)
      expect(exporter.entities.first[:id]).to eq('https://www.ammitto.org/entity/un/KPi.066')
      expect(exporter.entities.first[:ref]).to eq('un/KPi.066')
      expect(exporter.entities.first[:type]).to eq('person')
      expect(exporter.entities.first[:authority]).to eq('un')
      expect(exporter.entities.first[:status]).to eq('active')
    end

    it 'extracts multiple names' do
      entity = {
        '@id' => 'https://www.ammitto.org/entity/un/test',
        'entityType' => 'person',
        'names' => [
          { 'fullName' => 'John Doe', 'isPrimary' => true },
          { 'fullName' => 'J. Doe' }
        ],
        'aliases' => [
          { 'name' => 'Johnny' },
          'name' => 'JD'
        ]
      }

      entry = {
        'authority' => { '@id' => 'https://www.ammitto.org/authority/un' },
        'status' => 'active'
      }

      exporter.add(entity, entry)

      expect(exporter.entities.first[:names]).to include('John Doe', 'J. Doe', 'Johnny')
      expect(exporter.entities.first[:primaryName]).to eq('John Doe')
    end

    it 'extracts country from various sources' do
      entity = {
        '@id' => 'https://www.ammitto.org/entity/un/test',
        'entityType' => 'person',
        'names' => [{ 'fullName' => 'Test' }],
        'nationalities' => [{ 'countryCode' => 'KP' }]
      }

      entry = {
        'authority' => { '@id' => 'https://www.ammitto.org/authority/un' },
        'status' => 'active'
      }

      exporter.add(entity, entry)

      expect(exporter.entities.first[:country]).to eq('KP')
    end

    it 'extracts birth year for persons' do
      entity = {
        '@id' => 'https://www.ammitto.org/entity/un/test',
        'entityType' => 'person',
        'names' => [{ 'fullName' => 'Test' }],
        'birthInfo' => [{ 'date' => '1984-01-08' }]
      }

      entry = {
        'authority' => { '@id' => 'https://www.ammitto.org/authority/un' },
        'status' => 'active'
      }

      exporter.add(entity, entry)

      expect(exporter.entities.first[:birthYear]).to eq('1984')
    end

    it 'extracts IMO for vessels' do
      entity = {
        '@id' => 'https://www.ammitto.org/entity/eu_vessels/test',
        'entityType' => 'vessel',
        'names' => [{ 'fullName' => 'Test Vessel' }],
        'identifiers' => [{ 'type' => 'IMO', 'value' => '1234567' }]
      }

      entry = {
        'authority' => { '@id' => 'https://www.ammitto.org/authority/eu_vessels' },
        'status' => 'active'
      }

      exporter.add(entity, entry)

      expect(exporter.entities.first[:imo]).to eq('1234567')
    end

    it 'updates facet counts' do
      entity = {
        '@id' => 'https://www.ammitto.org/entity/un/test',
        'entityType' => 'person',
        'names' => [{ 'fullName' => 'Test' }],
        'nationalities' => [{ 'countryCode' => 'KP' }]
      }

      entry = {
        'authority' => { '@id' => 'https://www.ammitto.org/authority/un' },
        'regime' => { '@id' => 'https://www.ammitto.org/regime/dprk', 'name' => 'DPRK' },
        'status' => 'active'
      }

      exporter.add(entity, entry)

      expect(exporter.facets[:authorities]['un']).to eq(1)
      expect(exporter.facets[:types]['person']).to eq(1)
      expect(exporter.facets[:countries]['KP']).to eq(1)
      expect(exporter.facets[:statuses]['active']).to eq(1)
    end
  end

  describe '#export' do
    before do
      # Add some test entities
      3.times do |i|
        entity = {
          '@id' => "https://www.ammitto.org/entity/un/test#{i}",
          'entityType' => i.even? ? 'person' : 'organization',
          'names' => [{ 'fullName' => "Test Entity #{i}", 'isPrimary' => true }]
        }

        entry = {
          'authority' => { '@id' => 'https://www.ammitto.org/authority/un' },
          'regime' => { '@id' => 'https://www.ammitto.org/regime/dprk', 'name' => 'DPRK' },
          'status' => 'active'
        }

        exporter.add(entity, entry)
      end
    end

    it 'creates search-index.json' do
      exporter.export(output_dir)

      index_file = File.join(output_dir, 'search-index.json')
      expect(File.exist?(index_file)).to be true

      data = JSON.parse(File.read(index_file))
      expect(data['metadata']['totalEntities']).to eq(3)
      expect(data['entities'].length).to eq(3)
    end

    it 'creates facets directory' do
      exporter.export(output_dir)

      expect(Dir.exist?(File.join(output_dir, 'facets'))).to be true
    end

    it 'creates authority facets' do
      exporter.export(output_dir)

      facets_file = File.join(output_dir, 'facets', 'authorities.json')
      expect(File.exist?(facets_file)).to be true

      data = JSON.parse(File.read(facets_file))
      expect(data['facets']).to be_an(Array)
      expect(data['facets'].first['code']).to eq('un')
      expect(data['facets'].first['count']).to eq(3)
    end

    it 'creates type facets' do
      exporter.export(output_dir)

      facets_file = File.join(output_dir, 'facets', 'types.json')
      expect(File.exist?(facets_file)).to be true

      data = JSON.parse(File.read(facets_file))
      expect(data['facets']).to be_an(Array)

      person_facet = data['facets'].find { |f| f['code'] == 'person' }
      expect(person_facet).not_to be_nil
      expect(person_facet['icon']).to eq('user')
    end

    it 'creates regime facets' do
      exporter.export(output_dir)

      facets_file = File.join(output_dir, 'facets', 'regimes.json')
      expect(File.exist?(facets_file)).to be true

      data = JSON.parse(File.read(facets_file))
      expect(data['facets']).to be_an(Array)
    end

    it 'creates country facets' do
      exporter.export(output_dir)

      facets_file = File.join(output_dir, 'facets', 'countries.json')
      expect(File.exist?(facets_file)).to be true

      data = JSON.parse(File.read(facets_file))
      expect(data['facets']).to be_an(Array)
    end

    it 'creates status facets' do
      exporter.export(output_dir)

      facets_file = File.join(output_dir, 'facets', 'statuses.json')
      expect(File.exist?(facets_file)).to be true

      data = JSON.parse(File.read(facets_file))
      expect(data['facets']).to be_an(Array)
    end
  end
end
