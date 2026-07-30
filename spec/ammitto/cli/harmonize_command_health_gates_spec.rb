# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'json'
require 'ammitto'
require 'ammitto/cli'
require 'ammitto/cli/harmonize_command'

RSpec.describe Ammitto::Cmd::HarmonizeCommand do
  let(:sources_dir) { Dir.mktmpdir('ammitto_gates_sources') }
  let(:output_dir) { Dir.mktmpdir('ammitto_gates_output') }
  let(:options) { { sources_dir: sources_dir, output_dir: output_dir } }
  let(:command) { described_class.new(options, ['us']) }

  after do
    FileUtils.rm_rf(sources_dir)
    FileUtils.rm_rf(output_dir)
  end

  # Write one processed us YAML file
  def write_us_yaml(basename, data)
    dir = File.join(sources_dir, 'data-us', 'processed')
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, basename), data.to_yaml)
  end

  def healthy_entity(uid, last_name)
    { 'uid' => uid, 'last_name' => last_name, 'sdn_type' => 'Individual' }
  end

  describe 'quality floors (integration)' do
    before { allow($stdout).to receive(:write) }

    it 'fails the gate for a single nameless entity (the us incident)' do
      write_us_yaml('entity.yaml', { 'uid' => '9999' })

      expect { command.run }.to raise_error(
        Thor::Error, /us: named-entity ratio 0\.00 below floor/
      )
    end

    it 'fails the gate when entity ids collapse (jp-style)' do
      write_us_yaml('a.yaml', healthy_entity('5555', 'DOE'))
      write_us_yaml('b.yaml', healthy_entity('5555', 'ROE'))
      write_us_yaml('c.yaml', healthy_entity('5555', 'POE'))

      expect { command.run }.to raise_error(
        Thor::Error, /us: unique-id ratio 0\.33 below floor/
      )
    end

    it 'passes healthy named entities with distinct ids' do
      write_us_yaml('a.yaml', healthy_entity('1000', 'DOE'))
      write_us_yaml('b.yaml', healthy_entity('1001', 'ROE'))

      expect { command.run }.not_to raise_error
    end

    it 'exempts quality floors for --allow-empty sources' do
      options[:allow_empty] = 'us'
      write_us_yaml('entity.yaml', { 'uid' => '9999' })

      expect { command.run }.not_to raise_error
    end

    it 'attaches quality metrics to the per-source result contract' do
      write_us_yaml('a.yaml', healthy_entity('1000', 'DOE'))

      captured = nil
      allow(command).to receive(:enforce_health_gates)
        .and_wrap_original do |original, results|
          captured = results
          original.call(results)
        end

      command.run

      quality = captured.first[:quality]
      expect(quality).to include(
        unique_entities: 1,
        unique_id_ratio: 1.0,
        entity_nodes: 1,
        named_entities: 1,
        named_entity_ratio: 1.0
      )
    end
  end

  describe 'unparseable input files (integration)' do
    before { allow($stdout).to receive(:write) }

    def write_raw(basename, text)
      dir = File.join(sources_dir, 'data-us', 'processed')
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, basename), text)
    end

    let(:broken) { "uid: '1\n  bad: [unclosed\n" }

    it 'fails the gate even when the source is --allow-empty' do
      options[:allow_empty] = 'us'
      write_us_yaml('good.yaml', healthy_entity('1000', 'DOE'))
      write_raw('broken.yaml', broken)

      expect { command.run }.to raise_error(
        Thor::Error, /us: 1 file\(s\) failed to transform/
      )
    end

    it 'keeps the other files entities instead of failing the source' do
      write_us_yaml('good.yaml', healthy_entity('1000', 'DOE'))
      write_raw('broken.yaml', broken)

      captured = nil
      allow(command).to receive(:enforce_health_gates)
        .and_wrap_original do |original, results|
          captured = results
          original.call(results)
        end

      expect { command.run }.to raise_error(Thor::Error)
      expect(captured.first).to include(status: :success, entities: 1)
      expect(captured.first[:errors].first).to match(/broken\.yaml/)
    end
  end

  describe 'summary and gate agreement (integration)' do
    it 'prints the quality failure as failed before raising' do
      write_us_yaml('entity.yaml', { 'uid' => '9999' })

      expect do
        command.run
      rescue Thor::Error
        nil
      end.to output(/0 succeeded, 1 failed/).to_stdout
    end
  end

  describe '#aggregate_name_metrics' do
    def write_aggregate(content)
      FileUtils.mkdir_p(File.join(output_dir, 'sources'))
      File.write(File.join(output_dir, 'sources', 'us.jsonld'), content)
    end

    def metrics
      command.send(:aggregate_name_metrics, :us, output_dir)
    end

    it 'reports an unparseable aggregate instead of crashing' do
      write_aggregate('{oops')

      expect(metrics).to eq(aggregate_invalid: true)
    end

    it 'reports wrong-shaped JSON documents as invalid' do
      ['null', '[]', '{"@graph": {}}', '{"nograph": []}',
       '{"@graph": []}', '{"@graph": ["scalar"]}'].each do |content|
        write_aggregate(content)

        expect(metrics).to eq(aggregate_invalid: true), content
      end
    end

    it 'counts only non-blank String names as usable' do
      write_aggregate(JSON.generate(
                        '@graph' => [
                          { '@id' => 'https://x.org/entity/us/1',
                            'names' => [{ 'fullName' => 0 }, {}] },
                          { '@id' => 'https://x.org/entity/us/2',
                            'names' => [], 'name' => '   ' }
                        ]
                      ))

      expect(metrics).to include(named_entities: 0,
                                 named_entity_ratio: 0.0)
    end

    it 'returns empty metrics when the aggregate is missing' do
      expect(metrics).to eq({})
    end
  end

  describe '#quality_floor_failures' do
    it 'fails an invalid aggregate' do
      result = { code: :us, entities: 1,
                 quality: { aggregate_invalid: true } }

      expect(command.send(:quality_floor_failures, result))
        .to contain_exactly(/not a usable JSON-LD aggregate/)
    end

    it 'reports both floors when both are broken' do
      result = {
        code: :us, entities: 4,
        quality: { unique_entities: 1, unique_id_ratio: 0.25,
                   entity_nodes: 1, named_entities: 0,
                   named_entity_ratio: 0.0 }
      }

      failures = command.send(:quality_floor_failures, result)

      expect(failures).to contain_exactly(/unique-id ratio/,
                                          /named-entity ratio/)
    end

    # Both metrics sit exactly on their floors: the floors are inclusive,
    # so a regression from < to <= in either check fails this example
    it 'passes metrics at the floors' do
      result = {
        code: :us, entities: 2,
        quality: { unique_entities: 1, unique_id_ratio: 0.5,
                   entity_nodes: 10, named_entities: 9,
                   named_entity_ratio: 0.9 }
      }

      expect(command.send(:quality_floor_failures, result)).to be_empty
    end
  end

  describe '#print_summary' do
    # A healthy served aggregate so a clean source passes the floors
    def write_healthy_aggregate(code)
      FileUtils.mkdir_p(File.join(output_dir, 'sources'))
      File.write(
        File.join(output_dir, 'sources', "#{code}.jsonld"),
        JSON.generate(
          '@graph' => [{ '@id' => "https://x.org/entity/#{code}/1",
                         'names' => [{ 'fullName' => 'Named' }] }]
        )
      )
    end

    it 'counts a source with per-file errors as failed' do
      results = [{ code: :ch, status: :success, entities: 3, entries: 3,
                   errors: ['x.yml: boom'] }]

      expect { command.send(:print_summary, results) }
        .to output(/0 succeeded, 1 failed/).to_stdout
    end

    it 'lists the per-file failure reason' do
      results = [{ code: :ch, status: :success, entities: 3, entries: 3,
                   errors: ['x.yml: boom', 'y.yml: kaboom'] }]

      expect { command.send(:print_summary, results) }
        .to output(/ch: 2 file\(s\) failed to transform \(first: x\.yml: boom\)/)
        .to_stdout
    end

    it 'still counts clean sources as succeeded' do
      write_healthy_aggregate(:au)
      results = [{ code: :au, status: :success, entities: 3, entries: 3 },
                 { code: :ch, status: :error, error: 'nope' }]

      expect { command.send(:print_summary, results) }
        .to output(/1 succeeded, 1 failed.*ch: nope/m).to_stdout
    end

    it 'counts a quality-floor failure as failed, matching the gates' do
      results = [{ code: :us, status: :success, entities: 4, entries: 4,
                   quality: { named_entity_ratio: 0.0, named_entities: 0,
                              entity_nodes: 4 } }]
      write_healthy_aggregate(:us)
      allow(command).to receive(:attach_quality_metrics)

      expect { command.send(:print_summary, results) }
        .to output(/0 succeeded, 1 failed.*us: named-entity ratio/m)
        .to_stdout
    end

    # An --allow-empty source must not be printed as "failed" on a run
    # that exits 0: the counts have to match what the gates will raise on
    it 'reports an exempted errored source as exempted, not failed' do
      options[:allow_empty] = 'ch'
      results = [{ code: :ch, status: :error, error: 'No input directory found' }]

      expect { command.send(:print_summary, results) }
        .to output(
          /0 succeeded, 0 failed, 1 exempted.*Exempted sources \(--allow-empty\):\s+ch: No input directory found/m
        ).to_stdout
      expect(results.first[:gate_failures]).to be_empty
    end

    it 'keeps a per-file failure in the failed count even when exempted' do
      options[:allow_empty] = 'ch'
      results = [{ code: :ch, status: :success, entities: 3, entries: 3,
                   errors: ['x.yml: boom'] }]

      expect { command.send(:print_summary, results) }
        .to output(/0 succeeded, 1 failed, 0 exempted/).to_stdout
    end

    it 'prints deduplicated graph totals from the exporter stats' do
      exporter = instance_double(
        Ammitto::Serialization::JsonLdGraphExporter,
        stats: { total_entities: 10, total_entries: 12 }
      )
      command.instance_variable_set(:@exporter, exporter)
      results = [{ code: :au, status: :success, entities: 14, entries: 14 }]

      expect { command.send(:print_summary, results) }
        .to output(/Graph totals: 10 entities, 12 entries \(deduplicated\)/)
        .to_stdout
    end
  end
end
