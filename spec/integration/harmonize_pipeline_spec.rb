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
    expect(person['@id']).to eq('https://www.ammitto.org/entity/eu/eu55')
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

  it 'is strict by default: any zero-entity source fails the gate' do
    cmd = Ammitto::Cmd::HarmonizeCommand.new(
      { output_dir: File.join(@workdir, 'api', 'v1') }, ['jp']
    )
    zero = [{ code: :jp, status: :success, entities: 0, entries: 0 }]
    expect { cmd.send(:enforce_health_gates, zero) }
      .to raise_error(Thor::Error, /jp: produced 0 entities/)
  end

  it 'exempts only the sources named in --allow-empty' do
    cmd = Ammitto::Cmd::HarmonizeCommand.new(
      { output_dir: File.join(@workdir, 'api', 'v1'), allow_empty: 'jp,cn' }, ['jp']
    )
    allowed = [{ code: :jp, status: :success, entities: 0, entries: 0 }]
    expect { cmd.send(:enforce_health_gates, allowed) }.not_to raise_error

    unlisted = [{ code: :uk, status: :success, entities: 0, entries: 0 }]
    expect { cmd.send(:enforce_health_gates, unlisted) }
      .to raise_error(Thor::Error, /uk: produced 0 entities/)
  end

  it 'rejects unknown source codes in --allow-empty before any processing' do
    write_eu_fixture(@workdir)
    out = File.join(@workdir, 'api', 'v1')
    cmd = Ammitto::Cmd::HarmonizeCommand.new(
      { sources_dir: @workdir, output_dir: out, allow_empty: 'zz' }, ['eu']
    )
    expect { cmd.run }
      .to raise_error(Thor::Error, /Unknown sources in --allow-empty: zz/)
    expect(Dir.exist?(out)).to be(false) # failed fast: nothing was written
  end

  it 'treats a nil, empty, or whitespace flag as fully strict' do
    [nil, '', '  ', ',,'].each do |value|
      cmd = Ammitto::Cmd::HarmonizeCommand.new(
        { output_dir: File.join(@workdir, 'api', 'v1'), allow_empty: value }, ['uk']
      )
      expect(cmd.send(:allowed_empty_sources)).to eq([])
    end
  end

  it 'parses mixed case, whitespace, and stray commas in --allow-empty' do
    cmd = Ammitto::Cmd::HarmonizeCommand.new(
      { output_dir: File.join(@workdir, 'api', 'v1'), allow_empty: ' CN ,, ru , ' }, ['uk']
    )
    expect(cmd.send(:allowed_empty_sources)).to eq(%i[cn ru])
  end

  it 'fails on a missing aggregate for sources not in --allow-empty' do
    cmd = Ammitto::Cmd::HarmonizeCommand.new(
      { output_dir: File.join(@workdir, 'api', 'v1') }, ['uk']
    )
    produced_without_aggregate = [{ code: :uk, status: :success, entities: 3, entries: 3 }]
    expect { cmd.send(:enforce_health_gates, produced_without_aggregate) }
      .to raise_error(Thor::Error, /uk: per-source aggregate/)
  end

  it 'never exempts per-file transform errors, even for allowed sources' do
    cmd = Ammitto::Cmd::HarmonizeCommand.new(
      { output_dir: File.join(@workdir, 'api', 'v1'), allow_empty: 'jp' }, ['jp']
    )
    with_errors = [{ code: :jp, status: :success, entities: 2, entries: 2,
                     errors: ['x.yaml: transform produced incomplete entity/entry pair'] }]
    expect { cmd.send(:enforce_health_gates, with_errors) }
      .to raise_error(Thor::Error, /jp: 1 file\(s\) failed to transform/)

    error_status_with_errors = [{ code: :jp, status: :error, error: 'partial',
                                  errors: ['y.yaml: transform produced invalid result (String)'] }]
    expect { cmd.send(:enforce_health_gates, error_status_with_errors) }
      .to raise_error(Thor::Error, /jp: 1 file\(s\) failed to transform/)
  end

  it 'wires --allow-empty through the real CLI (rejection path)' do
    expect do
      expect { Ammitto::CLI.start(%w[harmonize eu --allow-empty zz]) }
        .to raise_error(SystemExit)
    end.to output(/Unknown sources in --allow-empty: zz/).to_stderr
  end

  it 'wires --allow-empty through the real CLI (exemption path)' do
    FileUtils.mkdir_p(File.join(@workdir, 'data-jp', 'processed'))
    out = File.join(@workdir, 'api', 'v1')
    expect do
      Ammitto::CLI.start(['harmonize', 'jp', '--allow-empty', 'jp',
                          '--sources-dir', @workdir, '--output-dir', out])
    end.not_to raise_error
  end

  it 'exempts allowed sources from error-status and aggregate checks too' do
    cmd = Ammitto::Cmd::HarmonizeCommand.new(
      { output_dir: File.join(@workdir, 'api', 'v1'), allow_empty: 'jp' }, ['jp']
    )
    errored = [{ code: :jp, status: :error, error: 'No YAML files found' }]
    expect { cmd.send(:enforce_health_gates, errored) }.not_to raise_error

    produced_without_aggregate = [{ code: :jp, status: :success, entities: 3, entries: 3 }]
    expect { cmd.send(:enforce_health_gates, produced_without_aggregate) }
      .not_to raise_error
  end
end
