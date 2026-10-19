# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'ammitto/validation/output_validator'
require 'ammitto/serialization/json_ld_graph_exporter'
require 'ammitto/serialization/search_index_exporter'
require 'ammitto/serialization/ontology_exporter'

RSpec.describe Ammitto::Validation::OutputValidator do
  around do |example|
    Dir.mktmpdir('ammitto-output-contracts') do |dir|
      @output_dir = dir
      example.run
    end
  end

  def validator
    described_class.new(output_dir: @output_dir)
  end

  def write(relative, data)
    path = File.join(@output_dir, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate(data))
    path
  end

  def entity(kind = 'person')
    { '@context' => Ammitto::Schema::Context.context_url,
      '@id' => "https://www.ammitto.org/entity/eu/#{kind}",
      '@type' => "#{kind.capitalize}Entity", 'entityType' => kind,
      'names' => [{ '@type' => 'NameVariant', 'fullName' => 'Example', 'isPrimary' => true }] }
  end

  def entry(kind = 'person')
    { '@id' => "https://www.ammitto.org/entry/eu/list/#{kind}",
      '@type' => 'SanctionEntry', 'entityId' => entity(kind)['@id'],
      'authority' => { 'id' => 'eu', 'name' => 'European Union', 'countryCode' => 'EU' },
      'regime' => { 'code' => 'test', 'name' => 'Test regime' }, 'status' => 'active',
      'legalBases' => [{ '@type' => 'LegalInstrument', 'identifier' => 'act', 'type' => 'law' }],
      'effects' => [{ '@type' => 'SanctionEffect', 'effectType' => 'asset_freeze' }],
      'announcement' => { '@type' => 'OfficialAnnouncement', 'documentId' => 'DOC',
                          'publishDate' => '2024-02', 'publisher' => 'eu/office', 'documentType' => 'eu/order' } }
  end

  def export_families
    graph = Ammitto::Serialization::JsonLdGraphExporter.new(output_dir: @output_dir)
    search = Ammitto::Serialization::SearchIndexExporter.new
    ontology = Ammitto::Serialization::OntologyExporter.new
    %w[person organization vessel aircraft].each do |kind|
      node = entity(kind)
      record = entry(kind)
      graph.add_node(entity: node, entry: record, source: :eu)
      search.add(node, record)
    end
    graph.add_document_type(
      '@id' => 'https://www.ammitto.org/document-type/eu/order',
      '@context' => Ammitto::Schema::Context.context_url,
      '@type' => 'DocumentType', 'identifier' => 'eu/order',
      'name' => [{ 'value' => 'Order', 'lang' => 'en' }]
    )
    graph.add_organization(
      '@id' => 'https://www.ammitto.org/organization/eu/office',
      '@context' => Ammitto::Schema::Context.context_url,
      '@type' => 'Organization', 'identifier' => 'eu/office',
      'name' => [{ 'value' => 'Office', 'lang' => 'en' }]
    )
    group = Ammitto::Ontology::Sanction::SanctionGroup.new(
      id: 'https://www.ammitto.org/group/eu/doc',
      entry_ids: ['https://www.ammitto.org/entry/eu/list/person'], entity_count: 1
    )
    graph.add_group(group, source: :eu)
    graph.export(cleanup: false)
    search.export(@output_dir)
    ontology.export(@output_dir)
    graph.export_manifest
    graph.written_paths.to_a + search.output_paths + ontology.output_paths
  end

  it 'validates every file the real exporters emit, including supporting metadata and all four entity types' do
    paths = export_families
    disk_paths = Dir.glob(File.join(@output_dir, '**', '*.{json,jsonld,ttl}'))
    expect(paths.sort).to eq(disk_paths.sort)
    result = validator.validate_files(paths)
    expect(result.errors).to eq([])
    expect(result.details[:files]).to eq(disk_paths.length)
  end

  it 'validates generated ontology examples as canonical standalone entities' do
    export_families
    instance = validator
    %w[person organization vessel].each do |kind|
      data = JSON.parse(File.read(File.join(@output_dir, "ontology/examples/#{kind}.jsonld")))
      canonical_path = write("node/entity/examples/#{kind}.jsonld", data)
      expect(instance.validate_files([canonical_path]).errors).to eq([])
    end
  end

  it 'rejects newline-bearing language-map keys while preserving valid language tags' do
    legal = { '@context' => Ammitto::Schema::Context.context_url,
              '@id' => 'https://www.ammitto.org/legal-instrument/cn/act',
              '@type' => 'LegalInstrument', 'identifier' => 'act' }
    instance = validator
    valid = legal.merge('title' => [{ 'en' => 'Title', 'ja' => '表題', 'zh-Hans' => '标题' }])
    path = write('node/legal-instrument/cn/act.jsonld', valid)
    expect(instance.validate_files([path]).valid?).to be true
    ["en\njunk", "junk\nen", "en\n", "en\r", "en\r\n"].each do |key|
      File.write(path, JSON.generate(legal.merge('title' => [{ key => 'Title' }])))
      expect(instance.validate_files([path]).valid?).to be(false), key.inspect
    end
  end

  it 'rejects newline-bearing source keys in statistics' do
    export_families
    path = File.join(@output_dir, 'stats.json')
    data = JSON.parse(File.read(path))
    source = data.fetch('sources').keys.first
    instance = validator
    expect(instance.validate_files([path]).valid?).to be true
    ["eu\nBAD", "BAD\neu", "eu\n", "eu\r", "eu\r\n"].each do |key|
      changed = JSON.parse(JSON.generate(data))
      changed['sources'][key] = changed['sources'].delete(source)
      File.write(path, JSON.generate(changed))
      expect(instance.validate_files([path]).valid?).to be(false), key.inspect
    end
  end

  it 'rejects excluded IRI characters and malformed escapes while preserving valid Unicode' do
    instance = validator
    bad = [0x80, 0x85, 0x9f, 0xfdd0, 0xfdef, 0xfff0, 0xfffd, 0xfffe, 0xffff,
           0x1fffe, 0x1ffff, 0x10fffe, 0x10ffff].map { |point| [point].pack('U') }
    good = [0xa0, 0x2028, 0x2029, 0xffef, 0x1fffd, 0x1f600].map { |point| [point].pack('U') }
    (bad + ['%ZZ', '%', '%2']).each do |suffix|
      path = write('node/entity/eu/person.jsonld', entity.merge('@id' => "https://example.org/#{suffix}"))
      expect(instance.validate_files([path]).valid?).to be(false), suffix.inspect
    end
    (good + ['日本', '%20']).each do |suffix|
      path = write('node/entity/eu/person.jsonld', entity.merge('@id' => "https://example.org/#{suffix}"))
      expect(instance.validate_files([path]).valid?).to be(true), suffix.inspect
    end
  end

  it 'rejects empty objects for every emitted JSON and JSON-LD family' do
    paths = export_families.reject { |path| path.end_with?('.ttl') }
    paths.each { |path| File.write(path, '{}') }
    result = validator.validate_files(paths)
    invalid_paths = result.errors.map { |error| error[:path] }.uniq.sort
    expect(invalid_paths).to eq(paths.sort)
  end

  it 'rejects unknown current artifact families, including unknown node indexes' do
    paths = [write('unexpected.json', {}), write('node/new-kind/index.jsonld', {})]
    expect(validator.validate_files(paths).errors)
      .to all(include(message: 'No output contract registered for artifact'))
  end

  it 'does not validate unrelated retained files' do
    write('unrelated.json', 'stale invalid payload')
    path = write('node/entity/eu/person.jsonld', entity)
    expect(validator.validate_files([path]).valid?).to be true
  end

  it 'reuses compiled contracts without leaking failure state between calls' do
    instance = validator
    allow(JSON::Validator).to receive(:new).and_call_original
    path = write('node/entity/eu/person.jsonld', entity.merge('entityType' => 'made_up'))
    expect(instance.validate_files([path]).valid?).to be false
    File.write(path, JSON.generate(entity))
    expect(instance.validate_files([path]).errors).to eq([])
    File.write(path, JSON.generate(entity.merge('entityType' => 'made_up')))
    expect(instance.validate_files([path]).valid?).to be false
    expect(JSON::Validator).to have_received(:new).once
  end

  it 'reuses only full valid payload proofs and misses changed fields under the same identity' do
    instance = validator
    path = write('node/entity/eu/person.jsonld', entity)
    first = instance.validate_files([path])
    expect(first.details).to include(cache_hits: 0, cache_misses: 1)
    expect(instance.validate_files([path]).details).to include(cache_hits: 1, cache_misses: 0)
    altered = entity
    altered['names'].first['fullName'] = 7
    File.write(path, JSON.generate(altered))
    2.times do
      result = instance.validate_files([path])
      expect(result.valid?).to be false
      expect(result.details).to include(cache_hits: 0, cache_misses: 1)
    end
    File.write(path, JSON.generate(entity))
    expect(instance.validate_files([path]).errors).to eq([])
  end

  it 'still requires standalone context when an identical aggregate node has a cached proof' do
    instance = validator
    data = entity.except('@context')
    aggregate = write('all.jsonld', '@context' => Ammitto::Schema::Context.context_url, '@graph' => [data])
    expect(instance.validate_files([aggregate]).valid?).to be true
    standalone = write('node/entity/eu/person.jsonld', data)
    result = instance.validate_files([standalone])
    expect(result.valid?).to be false
    expect(result.details[:cache_hits]).to eq(1)
  end

  {
    'unresolved references' => { '$ref' => '#/definitions/missing' },
    'cyclic references' => { '$ref' => '#/definitions/entity' },
    'reference siblings' => { '$ref' => '#/definitions/PersonEntity', 'required' => ['extra'] }
  }.each do |label, reference|
    it "rejects schema configuration with #{label}" do
      schema = JSON.parse(File.read(described_class::SCHEMA_PATH))
      schema['definitions']['entity'] = reference
      path = write('contract-test.json', schema)
      stub_const('Ammitto::Validation::OutputValidator::SCHEMA_PATH', path)
      expect { validator }.to raise_error(JSON::Schema::SchemaError)
    end
  end

  it 'checks every aggregate node through its typed schema and rejects unknown types' do
    path = write('all.jsonld', '@context' => Ammitto::Schema::Context.context_url,
                               '@graph' => [entity, entity('vessel')])
    instance = validator
    expect(instance.validate_files([path]).valid?).to be true
    unknown = entity('vessel').merge('@type' => 'NewEntity')
    File.write(path, JSON.generate('@context' => Ammitto::Schema::Context.context_url,
                                   '@graph' => [entity, unknown]))
    result = instance.validate_files([path])
    expect(result.valid?).to be false
    expect(result.errors.first[:message]).to include('#/@graph/1', 'NewEntity')
    File.write(path, JSON.generate('@context' => Ammitto::Schema::Context.context_url,
                                   '@graph' => [entity]))
    expect(instance.validate_files([path]).valid?).to be true
  end

  it 'fails closed for missing and malformed current files with their paths' do
    malformed = write('stats.json', {})
    File.write(malformed, '{')
    missing = File.join(@output_dir, 'all.jsonld')
    result = validator.validate_files([malformed, missing])
    expect(result.errors.map { |error| error[:path] }).to contain_exactly(malformed, missing)
    expect(result.errors.map { |error| error[:message] }.join).to include('JSON::ParserError', 'Errno::ENOENT')
  end

  it 'rejects invalid Turtle syntax using the RDF parser' do
    path = File.join(@output_dir, 'all.ttl')
    File.write(path, '<https://example.org/s> <https://example.org/p> "unterminated')
    result = validator.validate_files([path])
    expect(result.valid?).to be false
    expect(result.errors.first).to include(path: path)
  end

  it 'does not perform hidden logger device writes while parsing every Turtle statement' do
    path = File.join(@output_dir, 'all.ttl')
    File.write(path, '<https://example.org/s> <https://example.org/p> "valid" .')
    instance = validator
    writes = 0
    allow(RDF::Turtle::Reader).to receive(:open).and_wrap_original do |original, *args, **options, &block|
      expect(options[:validate]).to be true
      original.call(*args, **options) do |reader|
        allow(reader).to receive(:each_statement).and_call_original
        block.call(reader)
        expect(reader).to have_received(:each_statement).at_least(:once)
      end
    end
    trace = TracePoint.new(:call) do |event|
      writes += 1 if event.defined_class == Logger::LogDevice && event.method_id == :write
    end
    result = trace.enable { instance.validate_files([path]) }
    expect(result.errors).to eq([])
    expect(writes).to eq(0)
  end

  it 'isolates strict Turtle errors across files and repeated calls' do
    instance = validator
    bad = File.join(@output_dir, 'all.ttl')
    good = File.join(@output_dir, 'sources/uk.ttl')
    FileUtils.mkdir_p(File.dirname(good))
    File.write(bad, '<https://example.org/s> <https://example.org/p> "unterminated')
    File.write(good, '<https://example.org/s> <https://example.org/p> "valid" .')
    result = instance.validate_files([bad, good])
    expect(result.errors).to contain_exactly(include(path: bad, message: a_string_including('RDF::ReaderError')))
    expect(instance.validate_files([good]).errors).to eq([])
    expect(instance.validate_files([bad]).valid?).to be false
    File.write(bad, File.read(good))
    expect(instance.validate_files([bad, good]).errors).to eq([])
  end

  {
    'invalid escape' => 'ex:s ex:p "bad\P" .',
    'malformed Unicode escape' => 'ex:s ex:p "\uZZZZ" .',
    'invalid IRI' => '<https://example.org/a b> ex:p "text" .',
    'unknown prefix' => 'unknown:s ex:p "text" .',
    'missing object' => 'ex:s ex:p .',
    'trailing malformed statement' => 'ex:s ex:p "valid" . ex:s ex:p .',
    'invalid typed integer' => 'ex:s ex:p "abc"^^xsd:integer .',
    'invalid typed boolean' => 'ex:s ex:p "maybe"^^xsd:boolean .'
  }.tap do |malformed|
    it 'rejects supported strict Turtle malformed inputs without skipping trailing statements' do
      path = File.join(@output_dir, 'all.ttl')
      prefix = '@prefix ex: <https://example.org/> . @prefix xsd: <http://www.w3.org/2001/XMLSchema#> . '
      instance = validator
      malformed.each do |label, text|
        File.binwrite(path, prefix.b + text.b)
        result = instance.validate_files([path])
        expect(result.valid?).to be(false), label
        expect(result.errors).to contain_exactly(include(path: path, message: a_string_including('RDF::ReaderError')))
      end
    end
  end

  it 'preserves native strict Turtle invalid UTF-8 rejection' do
    path = File.join(@output_dir, 'all.ttl')
    File.binwrite(path, "<https://example.org/s> <https://example.org/p> \"\xff\" .".b)
    expect { validator.validate_files([path]) }.to raise_error(ArgumentError, 'invalid byte sequence in UTF-8')
  end

  it 'accepts source namespaces, partial dates, localized titles, and open birth-year bounds' do
    paths = export_families
    person_path = File.join(@output_dir, 'node/entity/eu/person.jsonld')
    person = JSON.parse(File.read(person_path))
    person['birthInfo'] = [{ '@type' => 'BirthInfo', 'date' => '1964', 'yearRangeTo' => 1980 }]
    File.write(person_path, JSON.generate(person))
    shard_path = File.join(@output_dir, 'search-index/eu.json')
    shard = JSON.parse(File.read(shard_path))
    shard['entities'].first['birthYears'] = [{ 'type' => 'date_range', 'from' => nil, 'to' => '1980', 'circa' => false }]
    File.write(shard_path, JSON.generate(shard))
    instrument_path = Dir.glob(File.join(@output_dir, 'node/legal-instrument/**/*.jsonld')).reject { |p| p.end_with?('index.jsonld') }.first
    instrument = JSON.parse(File.read(instrument_path))
    instrument['type'] = 'cn/departmental-order'
    instrument['title'] = [{ 'en' => 'Act' }, { 'zh-Hans' => '法律' }]
    File.write(instrument_path, JSON.generate(instrument))
    expect(validator.validate_files(paths).errors).to eq([])
  end

  it 'preserves native localized descriptions and rejects malformed localized values' do
    export_families
    path = File.join(@output_dir, 'node/entry/eu/list/person.jsonld')
    record = JSON.parse(File.read(path))
    record['effects'].first['description'] = [{ 'value' => "Text\ncontinued", 'lang' => 'en', 'is_primary' => true }]
    File.write(path, JSON.generate(record))
    instance = validator
    expect(instance.validate_files([path]).errors).to eq([])
    record['effects'].first['description'].first['is_primary'] = 'yes'
    File.write(path, JSON.generate(record))
    expect(instance.validate_files([path]).valid?).to be false
  end

  it 'validates recursive China and Japan legal content without accepting arbitrary objects' do
    chapter = { 'type' => 'chapter', 'index' => 1, 'label' => '第一章',
                'content' => [{ 'type' => 'clause', 'content' => ['Text'] }] }
    cn = { '@context' => Ammitto::Schema::Context.context_url,
           '@id' => 'https://www.ammitto.org/legal-instrument/cn/act', '@type' => 'LegalInstrument',
           'identifier' => 'act', 'content' => [chapter] }
    jp = cn.merge('@id' => 'https://www.ammitto.org/legal-instrument/jp/act')
    jp['content'] = [{ 'type' => 'chapter', 'index' => '1-1', 'label' => '第一章',
                       'content' => [{ 'type' => 'clause', 'index' => '2-2', 'label' => '第二条の二',
                                       'content' => [{ 'ja' => '本文', 'en' => 'Text' }] }] }]
    paths = [write('node/legal-instrument/cn/act.jsonld', cn), write('node/legal-instrument/jp/act.jsonld', jp)]
    instance = validator
    expect(instance.validate_files(paths).errors).to eq([])
    cn['content'].first['content'].first['unknown'] = true
    jp['content'].first['content'].first['content'].first['en'] = 7
    File.write(paths.first, JSON.generate(cn))
    File.write(paths.last, JSON.generate(jp))
    expect(instance.validate_files(paths).errors.map { |error| error[:path] }.uniq).to match_array(paths)
  end

  {
    'node/entity/eu/person.jsonld' => [
      ['missing node context', ->(d) { d.delete('@context') }],
      ['newline in IRI', ->(d) { d['@id'] += "\nnot an IRI" }],
      ['control byte in IRI', ->(d) { d['@id'] += "\u0000" }],
      ['embedded newline in date', ->(d) { d['birthInfo'] = [{ '@type' => 'BirthInfo', 'date' => "1964-02-30\n2020-01-01" }] }],
      ['invalid linked target IRI', ->(d) { d['linkedEntities'] = [{ '@type' => 'EntityLink', 'targetId' => 'notanIRI' }] }],
      ['wrong entity discriminator', ->(d) { d['entityType'] = 'aircraft' }],
      ['unknown field', ->(d) { d['birthdate'] = '1964' }],
      ['wrong name scalar', ->(d) { d['names'].first['fullName'] = 9 }],
      ['legacy name type', ->(d) { d['names'].first['@type'] = 'Name' }],
      ['object sanction reference', ->(d) { d['hasSanctionEntry'] = [{ '@id' => 'https://www.ammitto.org/entry/example' }] }],
      ['invalid calendar date', ->(d) { d['birthInfo'] = [{ '@type' => 'BirthInfo', 'date' => '1964-02-30' }] }],
      ['malformed birth information', ->(d) { d['birthInfo'] = [{ '@type' => 'BirthInfo', 'year' => '1964' }] }]
    ],
    'node/entity/eu/vessel.jsonld' => [
      ['legacy IMO field', ->(d) { d['imo'] = '1234567' }]
    ],
    'node/entry/eu/list/person.jsonld' => [
      ['invalid status', ->(d) { d['status'] = 'made_up' }],
      ['invalid group IRI', ->(d) { d['groupId'] = 'notanIRI' }],
      ['invalid modification target IRI', ->(d) { d['modifications'] = [{ '@type' => 'SanctionPeriodModification', 'targetAnnouncementId' => 'notanIRI' }] }],
      ['invalid URL IRI', ->(d) { d['announcement']['url'] = "https://example.org/\u0000" }],
      ['wrong reference object', ->(d) { d['authority'] = { 'name' => 'EU' } }],
      ['invalid effect', ->(d) { d['effects'].first['effectType'] = 'made_up' }],
      ['malformed period date', ->(d) { d['period'] = { '@type' => 'TemporalPeriod', 'listedDate' => 'yesterday' } }]
    ],
    'node/entity/index.jsonld' => [['invalid node reference', ->(d) { d['nodes'].first['@id'] = 'not an IRI' }]],
    'by-authority/eu.jsonld' => [['missing slice key', ->(d) { d.delete('authority') }]],
    'by-authority/index.jsonld' => [['invalid navigation IRI', ->(d) { d['available'] = ['notanIRI'] }]],
    'by-type/index.jsonld' => [['unknown navigation entity type', ->(d) { d['available'] = ['made_up'] }]],
    'by-status/index.jsonld' => [['unknown navigation status', ->(d) { d['available'] = ['made_up'] }]],
    'by-organization/eu/office.jsonld' => [['wrong announcement count', ->(d) { d['published'].first['entryCount'] = '4' }]],
    'stats.json' => [['negative count', ->(d) { d['total_entities'] = -1 }]],
    'search-index/eu.json' => [['wrong birth-year union', ->(d) { d['entities'].first['birthYears'] = [{ 'type' => 'date_range', 'from' => nil, 'to' => nil, 'circa' => false }] }]],
    'search-index/manifest.json' => [['unsafe shard path', ->(d) { d['shards'].first['file'] = '../outside.json' }]],
    'facets/types.json' => [
      ['wrong facet count', ->(d) { d['facets'].first['count'] = '3' }],
      ['unknown facet entity type', ->(d) { d['facets'].first['code'] = 'made_up' }]
    ],
    'facets/statuses.json' => [['unknown facet status', ->(d) { d['facets'].first['code'] = 'made_up' }]],
    'ontology/classes.jsonld' => [
      ['wrong class type', ->(d) { d['@graph'].first['@type'] = 'rdf:Property' }],
      ['wrong RDFS prefix', ->(d) { d['@context']['rdfs'] = 'https://example.org/' }],
      ['missing subclass IRI coercion', ->(d) { d['@context']['subClassOf'].delete('@type') }],
      ['wrong property list IRI coercion', ->(d) { d['@context']['properties']['@type'] = 'xsd:string' }],
      ['arbitrary metadata context term', ->(d) { d['@context']['unexpected'] = 'rdfs:label' }]
    ],
    'ontology/properties.jsonld' => [
      ['invalid property range IRI', ->(d) { d['@graph'].first['range'] = 'notanIRI' }],
      ['invalid usage class IRI', ->(d) { d['@graph'].first['usages'].first['class'] = 'SanctionEntry' }],
      ['wrong usage cardinality type', ->(d) { d['@graph'].first['usages'].first['isArray'] = 'false' }],
      ['missing property usages', ->(d) { d['@graph'].first.delete('usages') }],
      ['wrong usages JSON coercion', ->(d) { d['@context']['usages']['@type'] = '@id' }],
      ['wrong range IRI coercion', ->(d) { d['@context']['range']['@type'] = 'xsd:string' }],
      ['wrong domain IRI coercion', ->(d) { d['@context']['domain']['@type'] = 'xsd:string' }],
      ['wrong RDF prefix', ->(d) { d['@context']['rdf'] = 'https://example.org/' }],
      ['wrong label predicate', ->(d) { d['@context']['label'] = 'comment' }],
      ['wrong comment predicate', ->(d) { d['@context']['comment'] = 'label' }]
    ],
    'ontology/hierarchy.json' => [['malformed nested hierarchy', ->(d) { d['children'].first['children'] = 2 }]],
    'ontology/examples/person.jsonld' => [
      ['legacy name type', ->(d) { d['names'].first['@type'] = 'Name' }],
      ['object sanction reference', ->(d) { d['hasSanctionEntry'] = [{ '@id' => 'https://www.ammitto.org/entry/example' }] }]
    ],
    'ontology/examples/vessel.jsonld' => [
      ['wrong tonnage value type', ->(d) { d['tonnage']['grossTonnage'] = '50000' }],
      ['legacy IMO field', ->(d) { d['imo'] = d.delete('imoNumber') }]
    ],
    'index.jsonld' => [['missing catalogue byte count', ->(d) { d['entries'].find { |e| e.key?('bytes') }.delete('bytes') }]],
    'context.jsonld' => [['wrong birth-year coercion', ->(d) { d['@context']['yearRangeTo']['@type'] = 'xsd:string' }]],
    'all.jsonld' => [['invalid nested aggregate node', ->(d) { d['@graph'].find { |n| n['@type'] == 'SanctionEntry' }['status'] = 'made_up' }]]
  }.each do |relative, cases|
    cases.each do |label, mutate|
      it "rejects #{label} in #{relative}" do
        export_families
        path = File.join(@output_dir, relative)
        data = JSON.parse(File.read(path))
        mutate.call(data)
        File.write(path, JSON.generate(data))
        result = validator.validate_files([path])
        expect(result.valid?).to be false
        expect(result.errors).to all(include(path: path))
      end
    end
  end
end
