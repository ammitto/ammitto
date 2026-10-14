# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'ammitto/cli'
require 'ammitto/cli/harmonize_command'

RSpec.describe Ammitto::Cmd::HarmonizeCommand do
  around do |example|
    Dir.mktmpdir('ammitto-output-gate') do |dir|
      @workdir = dir
      example.run
    end
  end

  def options
    { sources_dir: @workdir, output_dir: File.join(@workdir, 'api'),
      report: File.join(@workdir, 'report.json'), combine: true }
  end

  def write_fixture
    dir = File.join(@workdir, 'data-eu', 'processed')
    FileUtils.mkdir_p(dir)
    person = Ammitto::Sources::Eu::SanctionEntity.from_yaml({
      'logical_id' => '55', 'eu_reference_number' => 'EU.55',
      'subject_type' => { 'code' => 'person' },
      'name_aliases' => [{ 'whole_name' => 'John Doe' }]
    }.to_yaml)
    File.write(File.join(dir, 'entity.yaml'), person.to_yaml)
  end

  def preserve_stale
    path = File.join(options[:output_dir], 'node/entity/eu/stale.jsonld')
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, 'retained earlier output')
    path
  end

  def corrupt_export(exporter_class, relative, payload)
    allow(exporter_class).to receive(:new).and_wrap_original do |constructor, *args|
      exporter = constructor.call(*args)
      allow(exporter).to receive(:export).and_wrap_original do |original, *export_args|
        original.call(*export_args)
        File.write(File.join(options[:output_dir], relative), payload)
      end
      exporter
    end
  end

  it 'reports invalid emitted bytes and prevents deferred stale cleanup' do
    write_fixture
    stale = preserve_stale
    corrupt_export(Ammitto::Serialization::SearchIndexExporter, 'search-index/eu.json', '{}')
    command = described_class.new(options, ['eu'])
    expect { command.run }.to raise_error(Thor::Error, %r{output validation failed.*search-index/eu.json}m)
    expect(File.read(stale)).to eq('retained earlier output')
    report = JSON.parse(File.read(options[:report]))
    expect(report['gates_passed']).to be false
    expect(report['output_validation']['valid']).to be false
    expect(report['output_validation']['errors']).to include(hash_including('path' => a_string_ending_with('search-index/eu.json')))
  end

  it 'rejects corrupted source aggregates as well as graph exporter outputs' do
    write_fixture
    allow(Ammitto::Serialization::TurtleExporter).to receive(:export).and_wrap_original do |original, **args|
      original.call(**args)
      File.write(args[:jsonld_path], '{}') if args[:jsonld_path].end_with?('/sources/eu.jsonld')
    end
    expect { described_class.new(options, ['eu']).run }
      .to raise_error(Thor::Error, %r{sources/eu.jsonld})
  end

  it 'rejects malformed Turtle and preserves earlier nodes' do
    write_fixture
    stale = preserve_stale
    corrupt_export(Ammitto::Serialization::OntologyExporter, 'all.ttl', 'not valid Turtle')
    expect { described_class.new(options, ['eu']).run }
      .to raise_error(Thor::Error, /output validation failed.*all.ttl/m)
    expect(File.exist?(stale)).to be true
  end

  it 'keeps source health failures as the primary diagnosis while recording output defects' do
    write_fixture
    corrupt_export(Ammitto::Serialization::SearchIndexExporter, 'search-index/eu.json', '{}')
    expect { described_class.new(options, %w[eu uk]).run }
      .to raise_error(Thor::Error, /health gate failed.*uk:/m)
    report = JSON.parse(File.read(options[:report]))
    expect(report['gates_passed']).to be false
    expect(report['output_validation']['valid']).to be false
    expect(report['sources'].find { |source| source['code'] == 'uk' }['gate_failures']).not_to be_empty
  end

  it 'never exempts invalid output with allow-empty' do
    write_fixture
    corrupt_export(Ammitto::Serialization::SearchIndexExporter, 'search-index/eu.json', '{}')
    expect { described_class.new(options.merge(allow_empty: 'eu'), ['eu']).run }
      .to raise_error(Thor::Error, /output validation failed/)
  end

  it 'validates the diagnostic report bytes before permitting cleanup' do
    write_fixture
    stale = preserve_stale
    command = described_class.new(options, ['eu'])
    allow(command).to receive(:write_report).and_wrap_original do |original, results|
      original.call(results)
      File.write(options[:report], '{}')
      nil
    end
    expect { command.run }.to raise_error(Thor::Error, /report validation failed/)
    expect(File.exist?(stale)).to be true
  end

  it 'refuses a report path that would overwrite an exported API artifact' do
    write_fixture
    opts = options.merge(report: File.join(options[:output_dir], 'stats.json'))
    expect { described_class.new(opts, ['eu']).run }
      .to raise_error(Thor::Error, /Report path overlaps an exported API artifact/)
    stats = JSON.parse(File.read(opts[:report]))
    expect(stats['total_entities']).to eq(1)
    expect(stats).not_to have_key('schema')
  end

  %w[symlink hardlink].each do |kind|
    it "refuses an external report #{kind} alias to an API artifact without cleanup" do
      write_fixture
      stale = preserve_stale
      command = described_class.new(options, ['eu'])
      allow(command).to receive(:write_report).and_wrap_original do |original, results|
        stats = File.join(options[:output_dir], 'stats.json')
        kind == 'symlink' ? File.symlink(stats, options[:report]) : File.link(stats, options[:report])
        original.call(results)
      end
      expect { command.run }.to raise_error(Thor::Error, /Report path overlaps/)
      expect(JSON.parse(File.read(File.join(options[:output_dir], 'stats.json')))['total_entities']).to eq(1)
      expect(File.read(stale)).to eq('retained earlier output')
    end
  end

  it 'refuses a report path over a retained artifact from a source absent this run' do
    write_fixture
    retained = File.join(options[:output_dir], 'sources/uk.jsonld')
    FileUtils.mkdir_p(File.dirname(retained))
    File.write(retained, 'retained UK aggregate')
    expect { described_class.new(options.merge(report: retained), ['eu']).run }
      .to raise_error(Thor::Error, /Report path overlaps/)
    expect(File.read(retained)).to eq('retained UK aggregate')
  end

  it 'writes a failing diagnostic and retains stale nodes when the packaged contract is missing' do
    write_fixture
    stale = preserve_stale
    stub_const('Ammitto::Validation::OutputValidator::SCHEMA_PATH', File.join(@workdir, 'missing-schema.json'))
    expect { described_class.new(options, ['eu']).run }
      .to raise_error(Thor::Error, /output validation failed.*ENOENT/m)
    report = JSON.parse(File.read(options[:report]))
    expect(report['gates_passed']).to be false
    expect(report['output_validation']['valid']).to be false
    expect(report['output_validation']['errors'].first['message']).to include('ENOENT')
    expect(File.exist?(stale)).to be true
  end

  it 'cleans stale nodes only after valid artifacts and diagnostics pass' do
    write_fixture
    stale = preserve_stale
    expect { described_class.new(options, ['eu']).run }.not_to raise_error
    expect(File.exist?(stale)).to be false
    report = JSON.parse(File.read(options[:report]))
    expect(report['gates_passed']).to be true
    expect(report['output_validation']).to include('valid' => true, 'errors' => [])
  end
end
