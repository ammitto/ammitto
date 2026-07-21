# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'json'
require 'ammitto/cli'
require 'ammitto/cli/harmonize_command'

# End-to-end pipeline protection: fetch-shaped YAML fixtures are harmonized
# through the real command, and the exported artifacts must match the
# canonical JSON-LD contract (camelCase context terms, @id/@type, per-source
# aggregates) that the website and Data::Repository consume.
RSpec.describe 'harmonize pipeline (integration)' do
  around do |example|
    Dir.mktmpdir do |dir|
      @workdir = dir
      example.run
    end
  end

  def write_eu_fixture(dir)
    processed = File.join(dir, 'data-eu', 'processed')
    FileUtils.mkdir_p(processed)

    person = Ammitto::Sources::Eu::SanctionEntity.from_yaml({
      'logical_id' => '55', 'eu_reference_number' => 'EU.55',
      'subject_type' => { 'code' => 'person' },
      'name_aliases' => [{ 'whole_name' => 'John Doe' }],
      'birthdates' => [{ 'birthdate' => '1964-07-17' }]
    }.to_yaml)
    File.write(File.join(processed, 'eu-55.yaml'), person.to_yaml)

    org = Ammitto::Sources::Eu::SanctionEntity.from_yaml({
      'logical_id' => '56', 'eu_reference_number' => 'EU.56',
      'subject_type' => { 'code' => 'enterprise' },
      'name_aliases' => [{ 'whole_name' => 'Acme Corp' }]
    }.to_yaml)
    File.write(File.join(processed, 'eu-56.yaml'), org.to_yaml)
  end

  def run_harmonize(sources, dir)
    options = { sources_dir: dir, output_dir: File.join(dir, 'api', 'v1') }
    Ammitto::Cmd::HarmonizeCommand.new(options, sources).run
  end

  it 'exports the canonical camelCase JSON-LD shape end to end' do
    write_eu_fixture(@workdir)
    expect { run_harmonize(['eu'], @workdir) }.not_to raise_error

    api = File.join(@workdir, 'api', 'v1')

    # Per-source aggregate exists (BaseSource + Data::Repository contract)
    aggregate = JSON.parse(File.read(File.join(api, 'sources', 'eu.jsonld')))
    expect(aggregate['@context']).to eq(Ammitto::Schema::Context.context_url)

    graph = aggregate['@graph']
    entities = graph.select { |n| n['@type'].to_s.end_with?('Entity') }
    expect(entities.length).to eq(2)

    person = entities.find { |e| e['@type'] == 'PersonEntity' }
    expect(person['@id']).to eq('https://www.ammitto.org/entity/eu/EU.55')
    expect(person['entityType']).to eq('person')
    expect(person['names'].first['fullName']).to eq('John Doe')
    expect(person['names'].first).to have_key('isPrimary')

    # Search index carries real names (the production regression of 2026)
    index = JSON.parse(File.read(File.join(api, 'search-index.json')))
    expect(index['entities'].length).to eq(2)
    expect(index['entities'].flat_map { |e| e['names'] }).to include('John Doe')
    expect(index['entities'].map { |e| e['primaryName'] }).to include('John Doe')

    # Context artifact is written next to the data
    context = JSON.parse(File.read(File.join(api, 'context.jsonld')))
    expect(context).to have_key('@context')

    # Stats agree with the graph
    stats = JSON.parse(File.read(File.join(api, 'stats.json')))
    expect(stats['total_entities']).to eq(2)
  end

  it 'harmonizes CH identities and AU vessels into correctly-typed entities' do
    ch_dir = File.join(@workdir, 'data-ch', 'processed')
    FileUtils.mkdir_p(ch_dir)
    person = Ammitto::Sources::Ch::Identity.from_yaml({
      'ssid' => '111',
      'names' => [{ 'name_parts' => [
        { 'name_part_type' => 'given-name', 'value' => 'Vladimir' },
        { 'name_part_type' => 'family-name', 'value' => 'Testov' }
      ] }]
    }.to_yaml)
    File.write(File.join(ch_dir, 'ch-111.yaml'), person.to_yaml)

    au_dir = File.join(@workdir, 'data-au', 'processed')
    FileUtils.mkdir_p(au_dir)
    vessel = Ammitto::Sources::Au::Vessel.from_yaml({
      'reference' => '7',
      'names' => [{ 'text' => 'SHIP X', 'name_type' => 'primary' }],
      'imo_number' => 'IMO 12345'
    }.to_yaml)
    File.write(File.join(au_dir, 'au-7.yaml'), vessel.to_yaml)

    expect { run_harmonize(%w[ch au], @workdir) }.not_to raise_error

    api = File.join(@workdir, 'api', 'v1')
    ch = JSON.parse(File.read(File.join(api, 'sources', 'ch.jsonld')))['@graph']
    ch_entity = ch.find { |n| n['@type'].to_s.end_with?('Entity') }
    expect(ch_entity['@type']).to eq('PersonEntity')
    expect(ch_entity['names'].first['fullName']).to include('Vladimir')

    au = JSON.parse(File.read(File.join(api, 'sources', 'au.jsonld')))['@graph']
    au_entity = au.find { |n| n['@type'].to_s.end_with?('Entity') }
    expect(au_entity['@type']).to eq('VesselEntity')
    expect(au_entity['imoNumber']).to eq('IMO 12345')
  end

  it 'fails the health gate when an active source produces no entities' do
    FileUtils.mkdir_p(File.join(@workdir, 'data-uk', 'processed'))

    expect { run_harmonize(['uk'], @workdir) }
      .to raise_error(Thor::Error, /uk/)
  end

  it 'does not fail the health gate for dormant sources' do
    dormant = Ammitto::Config::Defaults::DORMANT_SOURCES
    expect(dormant).to include(:jp, :un_vessels, :cn, :ru)
  end

  it 'exempts dormant zero-entity runs from every gate, including aggregates' do
    cmd = Ammitto::Cmd::HarmonizeCommand.new(
      { output_dir: File.join(@workdir, 'api', 'v1') }, ['jp']
    )
    dormant_ok = [{ code: :jp, status: :success, entities: 0, entries: 0 }]
    expect { cmd.send(:enforce_health_gates, dormant_ok) }.not_to raise_error

    active_zero = [{ code: :uk, status: :success, entities: 0, entries: 0 }]
    expect { cmd.send(:enforce_health_gates, active_zero) }
      .to raise_error(Thor::Error, /uk: produced 0 entities/)
  end
end
