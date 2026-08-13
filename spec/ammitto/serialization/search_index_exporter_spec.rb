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

    # An entity can carry one birth record per contributing source, and
    # the one holding the exact date is not reliably first. Reading only
    # `birthInfo.first` dropped a stated year whenever a location-only or
    # empty record preceded it — while the span path already scanned the
    # whole list, so a range was found where a more precise year was not.
    it 'finds an exact year in a birth record that is not the first' do
      entity = {
        '@id' => 'https://www.ammitto.org/entity/un/later-record',
        'entityType' => 'person',
        'names' => [{ 'fullName' => 'Test' }],
        'birthInfo' => [
          { 'city' => 'Pyongyang' },
          { 'date' => '1984-01-08' }
        ]
      }

      exporter.add(entity, 'authority' => { '@id' => 'https://www.ammitto.org/authority/un' },
                           'status' => 'active')

      expect(exporter.entities.first[:birthYear]).to eq('1984')
    end

    it 'still prefers the earliest record that states one' do
      entity = {
        '@id' => 'https://www.ammitto.org/entity/un/two-records',
        'entityType' => 'person',
        'names' => [{ 'fullName' => 'Test' }],
        'birthInfo' => [
          { 'year' => 1984 },
          { 'date' => '1990-01-08' }
        ]
      }

      exporter.add(entity, 'authority' => { '@id' => 'https://www.ammitto.org/authority/un' },
                           'status' => 'active')

      expect(exporter.entities.first[:birthYear]).to eq('1984')
    end

    # birthYear answers "born in this exact year". A span names no such
    # year, so it gets its own columns and birthYear stays absent — a
    # lower bound written there would let a record that never claimed a
    # year answer an exact-year query.
    context 'with a stated span of birth years' do
      def row_for(birth_info)
        exporter.add({
                       '@id' => 'https://www.ammitto.org/entity/eu/test',
                       'entityType' => 'person',
                       'names' => [{ 'fullName' => 'Test' }],
                       'birthInfo' => [birth_info]
                     },
                     { 'authority' => { '@id' => 'https://www.ammitto.org/authority/eu' },
                       'status' => 'active' })
        exporter.entities.first
      end

      it 'exports the bounds and omits birthYear entirely' do
        row = row_for({ 'yearRangeFrom' => 1953, 'yearRangeTo' => 1958 })

        expect(row[:birthYearFrom]).to eq('1953')
        expect(row[:birthYearTo]).to eq('1958')
        expect(row).not_to have_key(:birthYear)
      end

      it 'exports only the bound that exists, leaving the span open' do
        row = row_for({ 'yearRangeTo' => 1980 })

        expect(row[:birthYearTo]).to eq('1980')
        expect(row).not_to have_key(:birthYearFrom)
        expect(row).not_to have_key(:birthYear)
      end

      it 'reads the snake_case spelling too' do
        row = row_for({ 'year_range_from' => 1959, 'year_range_to' => 1965 })

        expect(row[:birthYearFrom]).to eq('1959')
        expect(row[:birthYearTo]).to eq('1965')
      end

      # A full-date span reaches this exporter only after the real
      # transformer derives its year bounds and the real serializer
      # names them, so this example crosses both boundaries rather than
      # hand-writing the hash they produce. Feeding a year-range hash
      # straight in would prove the indexer reads year bounds — which
      # was never in doubt — not that a date span supplies them.
      it 'exports year bounds derived from a serialized date span' do
        transformer = Ammitto::Transformers::BaseTransformer.new(:us)
        birth = transformer.send(:create_birth_info,
                                 date: '28 Feb 1962 to 28 Feb 1963')
        birth_node = Ammitto::Serialization::JsonLdSerializer
                     .new.send(:serialize_birth_info, birth)

        row = row_for(birth_node)

        expect(row[:birthYearFrom]).to eq('1962')
        expect(row[:birthYearTo]).to eq('1963')
        expect(row).not_to have_key(:birthYear)
      end

      # The same crossing for the OTHER span shape. A same-year span is
      # the only one that answers an exact-year query AND a range query,
      # so it is the only one where all five fields must appear at once
      # — and the example above, being cross-year, asserts birthYear is
      # ABSENT. Without this one a regression that dropped the scalar
      # year anywhere along the crossing would leave the suite green and
      # make every "born in 1962" search miss a person OFAC pinned to
      # 1962 twice over. Both date bounds are asserted on the node the
      # row is built from, so the finer precision is shown to survive
      # into the artifact rather than being reduced to its years.
      it 'exports birthYear and both bounds for a same-year date span' do
        transformer = Ammitto::Transformers::BaseTransformer.new(:us)
        birth = transformer.send(:create_birth_info,
                                 date: '01 Jan 1962 to 31 Dec 1962')
        birth_node = Ammitto::Serialization::JsonLdSerializer
                     .new.send(:serialize_birth_info, birth)

        row = row_for(birth_node)

        expect(birth_node['dateRangeFrom']).to eq(Date.new(1962, 1, 1))
        expect(birth_node['dateRangeTo']).to eq(Date.new(1962, 12, 31))
        expect(row[:birthYear]).to eq('1962')
        expect(row[:birthYearFrom]).to eq('1962')
        expect(row[:birthYearTo]).to eq('1962')
      end
    end

    # An entity can carry several birth records, and the span is not
    # always the first one. Reading only the first dropped it silently.
    context 'with several birth records' do
      def row_for_all(birth_infos)
        exporter.add({
                       '@id' => 'https://www.ammitto.org/entity/eu/multi',
                       'entityType' => 'person',
                       'names' => [{ 'fullName' => 'Test' }],
                       'birthInfo' => birth_infos
                     },
                     { 'authority' => { '@id' => 'https://www.ammitto.org/authority/eu' },
                       'status' => 'active' })
        exporter.entities.first
      end

      it 'finds a span that is not the first record' do
        row = row_for_all([{ 'year' => 1964 },
                           { 'yearRangeFrom' => 1953, 'yearRangeTo' => 1958 }])

        expect(row[:birthYearFrom]).to eq('1953')
        expect(row[:birthYearTo]).to eq('1958')
      end

      # Both bounds must come from ONE record. Taking a lower bound from
      # one and an upper from another would publish a span no source
      # ever stated.
      it 'takes both bounds from the same record' do
        row = row_for_all([{ 'yearRangeFrom' => 1953 },
                           { 'yearRangeFrom' => 1970, 'yearRangeTo' => 1975 }])

        expect(row[:birthYearFrom]).to eq('1953')
        expect(row).not_to have_key(:birthYearTo)
      end
    end

    it 'still exports birthYear for a stated single year, with no bounds' do
      exporter.add({
                     '@id' => 'https://www.ammitto.org/entity/eu/y',
                     'entityType' => 'person',
                     'names' => [{ 'fullName' => 'Test' }],
                     'birthInfo' => [{ 'year' => 1964 }]
                   },
                   { 'authority' => { '@id' => 'https://www.ammitto.org/authority/eu' },
                     'status' => 'active' })

      row = exporter.entities.first
      expect(row[:birthYear]).to eq('1964')
      expect(row).not_to have_key(:birthYearFrom)
      expect(row).not_to have_key(:birthYearTo)
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

      data = JSON.parse(File.read(File.join(output_dir, 'search-index.json')))
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

      data = JSON.parse(File.read(File.join(output_dir, 'search-index.json')))
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
