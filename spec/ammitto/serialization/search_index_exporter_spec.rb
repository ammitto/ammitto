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

    # JsonLdSerializer#serialize_authority emits 'id', never '@id'. Under
    # harmonize the graph exporter rewrites that hash into an '@id'
    # reference before the indexer sees it, but this exporter is also
    # documented for standalone use, and there the row must carry the
    # authority's own id, not the country it happens to sit in.
    it 'reads the authority id from an unrewritten authority hash' do
      entity = {
        '@id' => 'https://www.ammitto.org/entity/eu_vessels/9999999',
        'entityType' => 'vessel',
        'names' => [{ 'fullName' => 'Test Vessel', 'isPrimary' => true }]
      }

      entry = {
        '@id' => 'https://www.ammitto.org/entry/eu_vessels/9999999',
        'authority' => {
          '@type' => 'Authority',
          'id' => 'eu_vessels',
          'name' => 'EU Designated Vessels (via Denmark DMA)',
          'countryCode' => 'EU'
        },
        'status' => 'active'
      }

      exporter.add(entity, entry)

      expect(exporter.entities.first[:authority]).to eq('eu_vessels')
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

    describe 'birth-year value objects' do
      def year_value(value, circa: false)
        Ammitto::Serialization::BirthYear::Year.new(value, circa: circa)
      end

      def range_value(from: nil, to: nil, circa: false)
        Ammitto::Serialization::BirthYear::DateRange.new(
          from: from,
          to: to,
          circa: circa
        )
      end

      def row_for(birth_infos)
        exporter.add(
          {
            '@id' => 'https://www.ammitto.org/entity/eu/birth',
            'entityType' => 'person',
            'names' => [{ 'fullName' => 'Test' }],
            'birthInfo' => birth_infos
          },
          { 'authority' => { '@id' => 'https://www.ammitto.org/authority/eu' },
            'status' => 'active' }
        )
        exporter.entities.first
      end

      it 'exports one exact Year object' do
        row = row_for([{ 'date' => '1984-01-08' }])

        expect(row[:birthYears]).to eq([year_value('1984')])
        expect(row).not_to have_key(:birthYearKind)
        expect(row).not_to have_key(:birthCirca)
      end

      it 'finds a year after a location-only record' do
        row = row_for([{ 'city' => 'Pyongyang' }, { 'date' => '1984-01-08' }])

        expect(row[:birthYears]).to eq([year_value('1984')])
      end

      it 'exports a closed DateRange' do
        row = row_for([{ 'yearRangeFrom' => 1953, 'yearRangeTo' => 1958 }])

        expect(row[:birthYears]).to eq([range_value(from: 1953, to: 1958)])
      end

      it 'preserves a lower-only range direction' do
        row = row_for([{ 'yearRangeFrom' => 1953 }])

        expect(row[:birthYears]).to eq([range_value(from: 1953)])
      end

      it 'preserves an upper-only range direction' do
        row = row_for([{ 'yearRangeTo' => 1980 }])

        expect(row[:birthYears]).to eq([range_value(to: 1980)])
      end

      it 'preserves circa on a span object' do
        row = row_for([
                        { 'yearRangeFrom' => 1959, 'yearRangeTo' => 1965, 'circa' => true }
                      ])

        expect(row[:birthYears]).to eq(
          [range_value(from: 1959, to: 1965, circa: true)]
        )
      end

      it 'publishes every distinct candidate with its own circa flag' do
        row = row_for([
                        { 'year' => 1963 },
                        { 'year' => 1968, 'circa' => true }
                      ])

        expect(row[:birthYears]).to eq([
                                         year_value('1963'),
                                         year_value('1968', circa: true)
                                       ])
      end

      it 'deduplicates repeated years while retaining circa uncertainty' do
        row = row_for([
                        { 'year' => 1963 },
                        { 'year' => 1963, 'circa' => true }
                      ])

        expect(row[:birthYears]).to eq([year_value('1963', circa: true)])
      end

      it 'ignores malformed records and unrelated circa flags' do
        row = row_for([
                        { 'year' => 1963 },
                        { 'year' => 1968 },
                        { 'date' => 'not-a-date', 'circa' => true }
                      ])

        expect(row[:birthYears]).to eq([
                                         year_value('1963'),
                                         year_value('1968')
                                       ])
      end

      it 'keeps the first duplicate row birth array atomic' do
        exporter.add(
          {
            '@id' => 'https://www.ammitto.org/entity/eu/atomic',
            'entityType' => 'person',
            'birthInfo' => [{ 'year' => 1963 }]
          },
          { 'authority' => { '@id' => 'https://www.ammitto.org/authority/eu' },
            'status' => 'active' }
        )
        exporter.add(
          {
            '@id' => 'https://www.ammitto.org/entity/eu/atomic',
            'entityType' => 'person',
            'birthInfo' => [{ 'year' => 1968, 'circa' => true }]
          },
          { 'authority' => { '@id' => 'https://www.ammitto.org/authority/eu' },
            'status' => 'active' }
        )

        expect(exporter.entities.first[:birthYears])
          .to eq([year_value('1963')])
      end

      it 'uses the legacy flat birthDate only without birthInfo records' do
        row = row_for([{ 'city' => 'Pyongyang' }])

        expect(row).not_to have_key(:birthYears)

        fallback = {
          '@id' => 'https://www.ammitto.org/entity/eu/fallback',
          'entityType' => 'person',
          'birthDate' => '1970-03-04'
        }
        exporter.add(
          fallback,
          { 'authority' => { '@id' => 'https://www.ammitto.org/authority/eu' },
            'status' => 'active' }
        )

        expect(exporter.entities.last[:birthYears]).to eq([year_value('1970')])
      end

      it 'omits birthYears when no birth information exists' do
        row = row_for([])

        expect(row).not_to have_key(:birthYears)
      end

      it 'renders the same objects into the public JSON shape' do
        row = row_for([{ 'year' => 1968, 'circa' => true }])
        exporter.export(output_dir)

        data = JSON.parse(File.read(File.join(output_dir, 'search-index', 'eu.json')))
        exported = data['entities'].find { |entity| entity['id'] == row[:id] }

        expect(exported['birthYears']).to eq([
                                               {
                                                 'type' => 'year',
                                                 'value' => '1968',
                                                 'circa' => true
                                               }
                                             ])
        expect(exported).not_to have_key('birthYearKind')
        expect(exported).not_to have_key('birthCirca')
      end
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

  describe '#add deduplication' do
    let(:entity) do
      {
        '@id' => 'https://www.ammitto.org/entity/cn/test',
        'entityType' => 'organization',
        'names' => [{ 'fullName' => 'Test Corp', 'isPrimary' => true }]
      }
    end

    let(:entry) do
      {
        '@id' => 'https://www.ammitto.org/entry/cn/unreliable-entity-list/test',
        'authority' => { '@id' => 'https://www.ammitto.org/authority/cn' },
        'regime' => { '@id' => 'https://www.ammitto.org/regime/cn_unreliable', 'name' => 'CN' },
        'status' => 'active'
      }
    end

    it 'keeps one row per entity id for duplicate pairs' do
      exporter.add(entity, entry)
      exporter.add(entity, entry)

      expect(exporter.entities.length).to eq(1)
    end

    it 'recounts every facet from the deduplicated rows' do
      exporter.add(entity, entry)
      exporter.add(entity, entry)

      expect(exporter.facets[:authorities]['cn']).to eq(1)
      expect(exporter.facets[:list_types]['unreliable-entity-list']).to eq(1)
      expect(exporter.facets[:regimes]['cn_unreliable'][:count]).to eq(1)
      expect(exporter.facets[:types]['organization']).to eq(1)
      expect(exporter.facets[:statuses]['active']).to eq(1)
    end

    it 'unions names across repeated pairs' do
      exporter.add(entity, entry)
      exporter.add(entity.merge('names' => [{ 'fullName' => '测试公司' }]),
                   entry)

      row = exporter.entities.first
      expect(row[:names]).to contain_exactly('Test Corp', '测试公司')
    end

    it 'fills fields missing from the first-seen row' do
      exporter.add(entity, entry)
      exporter.add(entity.merge('nationalities' => [{ 'countryCode' => 'CN' }]),
                   entry)

      expect(exporter.entities.first[:country]).to eq('CN')
      expect(exporter.facets[:countries]['CN']).to eq(1)
    end

    it 'keeps first-seen values for fields both pairs carry' do
      exporter.add(entity, entry)
      exporter.add(entity, entry.merge('status' => 'delisted'))

      expect(exporter.entities.first[:status]).to eq('active')
      expect(exporter.facets[:statuses]).to eq('active' => 1)
    end

    it 'lets a later real status fill a first pair without one' do
      exporter.add(entity, entry.except('status'))
      exporter.add(entity, entry.merge('status' => 'delisted'))

      expect(exporter.entities.first[:status]).to eq('delisted')
      expect(exporter.facets[:statuses]).to eq('delisted' => 1)
    end

    it 'applies type and status defaults only after aggregation' do
      exporter.add(entity.except('entityType'), entry.except('status'))

      row = exporter.entities.first
      expect(row[:type]).to eq('person')
      expect(row[:status]).to eq('active')
      expect(exporter.facets[:types]).to eq('person' => 1)
    end

    it 'treats blank strings as missing so later data can fill them' do
      exporter.add(entity.merge('nationalities' => [{ 'countryCode' => '' }]),
                   entry)
      exporter.add(entity.merge('nationalities' => [{ 'countryCode' => 'CN' }]),
                   entry)

      expect(exporter.entities.first[:country]).to eq('CN')
      expect(exporter.facets[:countries]).to eq('CN' => 1)
    end

    it 'drops blank and wrong-typed names from the row' do
      noisy = entity.merge(
        'names' => [{ 'fullName' => 0, 'lastName' => '   ' },
                    { 'fullName' => 'Real Name' }],
        'name' => { 'oops' => true },
        'aliases' => [{ 'name' => 12.5 }, '', 'Real Alias']
      )

      exporter.add(noisy, entry)

      expect(exporter.entities.first[:names])
        .to contain_exactly('Real Name', 'Real Alias')
    end

    it 'keeps wrong-typed names out of the exported index' do
      exporter.add(entity.merge('names' => [{ 'fullName' => 0 }]), entry)
      exporter.export(output_dir)

      data = JSON.parse(File.read(File.join(output_dir, 'search-index', 'cn.json')))
      expect(data['entities'].first['names']).to eq([])
    end

    it 'unions only real names across repeated pairs' do
      exporter.add(entity.merge('names' => [{ 'fullName' => 0 }]), entry)
      exporter.add(entity, entry)

      expect(exporter.entities.first[:names]).to contain_exactly('Test Corp')
    end

    it 'falls back to id when @id is blank' do
      exporter.add(entity.merge('@id' => '', 'id' => 'real-id'), entry)

      expect(exporter.entities.map { |r| r[:id] }).to eq(['real-id'])
    end

    it 'never collapses distinct blank-id entities into one row' do
      exporter.add(entity.merge('@id' => ''), entry)
      exporter.add(entity.merge('@id' => '   '), entry)
      exporter.add(entity.merge('@id' => 0), entry)

      expect(exporter.entities).to be_empty
      expect(exporter.facets[:authorities]).to eq({})
    end

    it 'drops wrong-typed scalar values instead of crashing the export' do
      exporter.add(entity.merge('nationalities' => [{ 'countryCode' => 0 }]),
                   entry.merge('status' => {}))

      row = exporter.entities.first
      expect(row[:country]).to be_nil
      expect(row[:status]).to eq('active')
      expect(exporter.facets[:countries]).to eq({})
      expect { exporter.export(output_dir) }.not_to raise_error
    end

    it 'keeps wrong-typed regime names out of the facets' do
      exporter.add(entity,
                   entry.merge('regime' => {
                                 '@id' => 'https://www.ammitto.org/regime/x',
                                 'name' => { 'oops' => true }
                               }))

      expect(exporter.facets[:regimes]['x'][:name]).to be_nil
      expect { exporter.export(output_dir) }.not_to raise_error
    end

    # The lookup/discriminator fields reach #match and #downcase, so a
    # wrong-typed source value raises NoMethodError mid-harmonize rather
    # than dropping out of the row like the wrong-typed output fields
    it 'drops wrong-typed authority and regime lookups without crashing' do
      cases = [
        [{ 'authority' => { '@id' => 0 } }, :authority],
        [{ 'authority' => { 'countryCode' => {} } }, :authority],
        [{ 'regime' => { '@id' => [] } }, :regime],
        [{ 'regime' => { 'code' => {} } }, :regime],
        [{ '@id' => 0, 'list_type' => nil }, :listType]
      ]

      cases.each do |bad_entry, dropped|
        exporter = described_class.new
        expect { exporter.add(entity, entry.merge(bad_entry)) }
          .not_to raise_error
        expect(exporter.entities.first[dropped]).to be_nil
      end
    end

    it 'skips wrong-typed identifier types when reading the IMO' do
      vessel = {
        '@id' => 'https://www.ammitto.org/entity/eu_vessels/v1',
        'entityType' => 'vessel',
        'identifiers' => [{ 'type' => 0, 'value' => 'X' },
                          { 'document_type' => 5, 'value' => 'Y' },
                          { 'type' => 'imo', 'value' => 9_222_222 }]
      }

      exporter.add(vessel, entry)

      expect(exporter.entities.first[:imo]).to eq('9222222')
    end

    it 'falls back to the entry IRI when list_type is wrong-typed' do
      exporter.add(entity, entry.merge(
                             'list_type' => 0,
                             '@id' => 'https://www.ammitto.org/entry/cn/anti-sanction-list/1'
                           ))

      expect(exporter.entities.first[:listType]).to eq('anti-sanction-list')
    end

    it 'coerces numeric IMO numbers to strings' do
      vessel = {
        '@id' => 'https://www.ammitto.org/entity/eu_vessels/v1',
        'entityType' => 'vessel',
        'names' => [{ 'fullName' => 'Test Vessel' }],
        'identifiers' => [{ 'type' => 'IMO', 'value' => 9_111_111 }]
      }

      exporter.add(vessel, entry)

      expect(exporter.entities.first[:imo]).to eq('9111111')
    end

    it 'exports deduplicated totals' do
      exporter.add(entity, entry)
      exporter.add(entity, entry)
      exporter.export(output_dir)

      data = JSON.parse(File.read(File.join(output_dir, 'search-index', 'cn.json')))
      expect(data['metadata']['totalEntities']).to eq(1)
      expect(data['entities'].length).to eq(1)

      facets = JSON.parse(
        File.read(File.join(output_dir, 'facets', 'authorities.json'))
      )
      expect(facets['facets'].first['count']).to eq(1)
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

    it 'creates authority shards and a manifest' do
      exporter.export(output_dir)

      shard_file = File.join(output_dir, 'search-index', 'un.json')
      manifest_file = File.join(output_dir, 'search-index', 'manifest.json')

      expect(File.exist?(shard_file)).to be true
      expect(File.exist?(manifest_file)).to be true
      expect(File.exist?(File.join(output_dir, 'search-index.json'))).to be false

      shard = JSON.parse(File.read(shard_file))
      expect(shard['metadata']['totalEntities']).to eq(3)
      expect(shard['metadata']['sources']).to eq(1)
      expect(shard['entities'].length).to eq(3)

      manifest = JSON.parse(File.read(manifest_file))
      expect(manifest['metadata']['totalEntities']).to eq(3)
      expect(manifest['metadata']['sources']).to eq(1)
      expect(manifest['shards']).to eq(
        [{ 'code' => 'un', 'file' => 'un.json', 'count' => 3 }]
      )
    end

    it 'partitions rows by authority with shard-scoped metadata' do
      exporter.add(
        {
          '@id' => 'https://www.ammitto.org/entity/eu/extra',
          'entityType' => 'person',
          'names' => [{ 'fullName' => 'EU Entity' }]
        },
        {
          'authority' => { '@id' => 'https://www.ammitto.org/authority/eu' },
          'status' => 'active'
        }
      )

      exporter.export(output_dir)

      un = JSON.parse(File.read(File.join(output_dir, 'search-index', 'un.json')))
      eu = JSON.parse(File.read(File.join(output_dir, 'search-index', 'eu.json')))

      expect(un['metadata']).to include('totalEntities' => 3, 'sources' => 1)
      expect(eu['metadata']).to include('totalEntities' => 1, 'sources' => 1)
      expect(un['entities'].map { |row| row['authority'] }).to all(eq('un'))
      expect(eu['entities'].map { |row| row['authority'] }).to all(eq('eu'))

      manifest = JSON.parse(
        File.read(File.join(output_dir, 'search-index', 'manifest.json'))
      )
      expect(manifest['metadata']).to include('totalEntities' => 4, 'sources' => 2)
      expect(manifest['shards']).to contain_exactly(
        { 'code' => 'eu', 'file' => 'eu.json', 'count' => 1 },
        { 'code' => 'un', 'file' => 'un.json', 'count' => 3 }
      )
    end

    it 'preserves rows without an authority in an unknown shard' do
      orphan = described_class.new
      orphan.add(
        {
          '@id' => 'https://www.ammitto.org/entity/unknown/1',
          'entityType' => 'person',
          'names' => [{ 'fullName' => 'Unknown Entity' }]
        },
        { 'status' => 'active' }
      )

      orphan.export(output_dir)

      shard = JSON.parse(
        File.read(File.join(output_dir, 'search-index', 'unknown.json'))
      )
      expect(shard['metadata']).to include('totalEntities' => 1, 'sources' => 0)
      expect(shard['entities'].length).to eq(1)
    end

    it 'removes a pre-sharding monolithic search-index.json from a reused output dir' do
      leftover = File.join(output_dir, 'search-index.json')
      File.write(leftover, '{"entities":[]}')

      exporter.export(output_dir)

      expect(File.exist?(leftover)).to be false
    end

    it 'drops a shard left over from an authority no longer present in a rerun' do
      search_index_dir = File.join(output_dir, 'search-index')
      FileUtils.mkdir_p(search_index_dir)
      stale_shard = File.join(search_index_dir, 'stale.json')
      File.write(stale_shard, '{"entities":[]}')

      exporter.export(output_dir)

      expect(File.exist?(stale_shard)).to be false
      expect(File.exist?(File.join(search_index_dir, 'un.json'))).to be true
    end

    it 'falls back to the unknown shard for an authority with a path-traversal character' do
      exporter = described_class.new
      exporter.add(
        {
          '@id' => 'https://www.ammitto.org/entity/evil/1',
          'entityType' => 'person',
          'names' => [{ 'fullName' => 'Evil Entity' }]
        },
        { 'authority' => '../../etc/passwd', 'status' => 'active' }
      )

      exporter.export(output_dir)

      escaped_path = File.join(output_dir, '..', '..', 'etc', 'passwd.json')
      expect(File.exist?(escaped_path)).to be false
      shard = JSON.parse(
        File.read(File.join(output_dir, 'search-index', 'unknown.json'))
      )
      expect(shard['entities'].length).to eq(1)
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
