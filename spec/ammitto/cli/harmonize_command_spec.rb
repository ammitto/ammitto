# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'json'
require 'ammitto'
require 'ammitto/cli'
require 'ammitto/cli/harmonize_command'

RSpec.describe Ammitto::Cmd::HarmonizeCommand do
  let(:sources_dir) { Dir.mktmpdir('ammitto_harmonize_test') }
  let(:options) { { sources_dir: sources_dir } }
  let(:command) { described_class.new(options, ['us']) }

  after do
    FileUtils.rm_rf(sources_dir)
  end

  # Create a file (plus its parent directories) under sources_dir
  def write_file(*segments)
    path = File.join(sources_dir, *segments)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "---\nid: test\n")
    path
  end

  # Create a directory under sources_dir
  def make_dir(*segments)
    path = File.join(sources_dir, *segments)
    FileUtils.mkdir_p(path)
    path
  end

  describe '#find_input_dir' do
    def find_input(source = :us)
      command.send(:find_input_dir, source)
    end

    def find_input_dir(source = :us)
      find_input(source)&.first
    end

    it 'prefers a populated processed/ directory' do
      write_file('data-us', 'processed', 'entities', 'entity.yaml')
      make_dir('data-us', 'sources', 'sanction-lists', 'sdn-list')

      expect(find_input_dir)
        .to eq(File.join(sources_dir, 'data-us', 'processed'))
    end

    it 'falls through an empty processed/ to sources/sanction-lists' do
      make_dir('data-us', 'processed')
      entity = write_file('data-us', 'sources', 'sanction-lists',
                          'sdn-list', 'entity.yml')

      dir, files = find_input

      expect(dir).to eq(File.join(sources_dir, 'data-us', 'sources',
                                  'sanction-lists'))
      expect(files).to eq([entity])
    end

    it 'loads one-level and deeper files together when direct is empty' do
      make_dir('data-jp', 'processed')
      one = write_file('data-jp', 'sources', 'sanction-lists',
                       'fefta-list', 'entity.yml')
      deep = write_file('data-jp', 'sources', 'sanction-lists',
                        'mof-asset-freeze', '01-milosevic', '20260306.yml')

      _dir, files = find_input(:jp)

      expect(files).to contain_exactly(one, deep)
    end

    it 'falls through a processed/ holding only _index.yaml' do
      write_file('data-us', 'processed', '_index.yaml')
      write_file('data-us', 'sources', 'sanction-lists', 'sdn-list',
                 'entity.yml')

      expect(find_input_dir)
        .to eq(File.join(sources_dir, 'data-us', 'sources',
                         'sanction-lists'))
    end

    it 'falls through unusable processed/ and sanction-lists to raw' do
      write_file('data-us', 'processed', '_index.yaml')
      make_dir('data-us', 'sources', 'sanction-lists')
      write_file('data-us', 'raw', '2026-01-02', 'entity.yaml')

      expect(find_input_dir)
        .to eq(File.join(sources_dir, 'data-us', 'raw', '2026-01-02'))
    end

    it 'resolves hyphen-named repositories by eligibility' do
      make_dir('data-eu-vessels', 'processed')
      write_file('data-eu-vessels', 'sources', 'sanction-lists', 'list',
                 'vessel.yml')

      expect(find_input_dir(:eu_vessels))
        .to eq(File.join(sources_dir, 'data-eu-vessels', 'sources',
                         'sanction-lists'))
    end

    it 'prefers the underscore repository when both are eligible' do
      write_file('data-eu_vessels', 'processed', 'entity.yaml')
      write_file('data-eu-vessels', 'processed', 'entity.yaml')

      expect(find_input_dir(:eu_vessels))
        .to eq(File.join(sources_dir, 'data-eu_vessels', 'processed'))
    end

    it 'falls through to a usable cache when repo dirs are unusable' do
      make_dir('data-us', 'processed')
      cache_dir = make_dir('cache')
      options[:cache_dir] = cache_dir
      File.write(File.join(make_dir('cache', 'raw', 'us', '2026-01-01'),
                           'entity.yaml'), "---\nid: test\n")

      expect(find_input_dir)
        .to eq(File.join(cache_dir, 'raw', 'us', '2026-01-01'))
    end

    it 'reaches a usable cache past a raw/ dir without dated subdirs' do
      make_dir('data-us', 'raw')
      cache_dir = make_dir('cache')
      options[:cache_dir] = cache_dir
      File.write(File.join(make_dir('cache', 'raw', 'us', '2026-01-01'),
                           'entity.yaml'), "---\nid: test\n")

      expect(find_input_dir)
        .to eq(File.join(cache_dir, 'raw', 'us', '2026-01-01'))
    end

    it 'treats glob metacharacters in configured paths literally' do
      weird = File.join(sources_dir, 'we[i]rd')
      entity = File.join(weird, 'data-us', 'processed', 'entity.yaml')
      FileUtils.mkdir_p(File.dirname(entity))
      File.write(entity, "---\nid: test\n")
      options[:sources_dir] = weird

      dir, files = find_input

      expect(dir).to eq(File.join(weird, 'data-us', 'processed'))
      expect(files).to eq([entity])
    end

    it 'resolves each directory at most once per discovery call' do
      write_file('data-us', 'processed', '_index.yaml')

      resolved = []
      allow(command).to receive(:resolve_yaml_files)
        .and_wrap_original do |original, dir|
          resolved << dir
          original.call(dir)
        end

      find_input

      expect(resolved).to eq(resolved.uniq)
    end

    context 'when no candidate holds eligible YAML' do
      it 'returns the existing processed/ directory as before' do
        write_file('data-us', 'processed', '_index.yaml')

        expect(find_input_dir)
          .to eq(File.join(sources_dir, 'data-us', 'processed'))
      end

      it 'reports "No YAML files found" for that directory' do
        write_file('data-us', 'processed', '_index.yaml')

        result = command.send(:harmonize_source, :us)

        expect(result[:status]).to eq(:error)
        expect(result[:error]).to eq('No YAML files found')
      end

      it 'returns nil when nothing exists for the source' do
        options[:cache_dir] = make_dir('cache')

        expect(command.send(:find_input_dir, :us)).to be_nil
      end

      it 'keeps the legacy nil for a raw/ dir without dated subdirs' do
        make_dir('data-us', 'raw')
        options[:cache_dir] = make_dir('cache')

        expect(command.send(:find_input_dir, :us)).to be_nil
      end
    end

    context 'with an explicit input_dir option' do
      it 'prefers the per-source subdirectory and its eligible files' do
        input_dir = make_dir('input')
        entity = write_file('input', 'us', 'list', 'deep', 'entity.yml')
        options[:input_dir] = input_dir

        dir, files = find_input

        expect(dir).to eq(File.join(input_dir, 'us'))
        expect(files).to eq([entity])
      end

      it 'keeps subdirectory precedence even when it is empty' do
        input_dir = make_dir('input')
        make_dir('input', 'us')
        write_file('input', 'entity.yaml')
        write_file('input', 'uk', 'entity.yml')
        options[:input_dir] = input_dir

        dir, files = find_input

        expect(dir).to eq(File.join(input_dir, 'us'))
        expect(files).to eq([])
      end

      it 'does not fall through past an existing but empty path' do
        options[:input_dir] = make_dir('input')
        write_file('data-us', 'processed', 'entity.yaml')

        expect(find_input_dir).to eq(File.join(sources_dir, 'input'))
      end

      it 'never loads deeply nested sibling files from the base dir' do
        input_dir = make_dir('input')
        write_file('input', 'uk', 'deep', 'entity.yml')
        options[:input_dir] = input_dir

        dir, files = find_input

        expect(dir).to eq(input_dir)
        expect(files).to eq([])
      end

      it 'keeps the legacy one-level ingestion for the base fallback' do
        input_dir = make_dir('input')
        sibling = write_file('input', 'uk', 'entity.yml')
        options[:input_dir] = input_dir

        dir, files = find_input

        expect(dir).to eq(input_dir)
        expect(files).to eq([sibling])
      end

      it 'falls through to auto-detection when the path does not exist' do
        options[:input_dir] = File.join(sources_dir, 'missing')
        write_file('data-us', 'processed', 'entity.yaml')

        expect(find_input_dir)
          .to eq(File.join(sources_dir, 'data-us', 'processed'))
      end
    end

    context 'with non-regular YAML entries' do
      it 'keeps the legacy load-error path for the fallback dir' do
        junk = make_dir('data-us', 'processed', 'not-a-file.yaml')

        dir, files = command.send(:find_input_dir, :us)

        expect(dir).to eq(File.join(sources_dir, 'data-us', 'processed'))
        expect(files).to eq([junk])
      end

      it 'keeps them in the load list of a chosen directory' do
        entity = write_file('data-us', 'processed', 'entity.yaml')
        junk = make_dir('data-us', 'processed', 'broken.yaml')

        dir, files = command.send(:find_input_dir, :us)

        expect(dir).to eq(File.join(sources_dir, 'data-us', 'processed'))
        expect(files).to contain_exactly(entity, junk)
      end

      # The load error is attributed to the file that caused it rather
      # than to the whole source, so the readable files still count and
      # the run fails through the never-exempt per-file gate
      it 'surfaces the load error against the file for a mixed directory' do
        write_file('data-us', 'processed', 'entity.yaml')
        make_dir('data-us', 'processed', 'broken.yaml')

        result = command.send(:harmonize_source, :us)

        # A load error is a per-file defect, attributed to its file and
        # collected in :errors — the gate treats those as never exempt,
        # where a source-level :error would have been --allow-empty'able
        expect(result[:status]).to eq(:success)
        expect(result[:errors].join).to match(/broken\.yaml.*directory/i)
      end
    end
  end

  describe '#eligible_yaml_files' do
    def eligible_yaml_files(dir)
      command.send(:eligible_yaml_files, dir)
    end

    it 'collects entities/, flat, and one-level-nested YAML files' do
      dir = make_dir('data-us', 'processed')
      a = write_file('data-us', 'processed', 'entities', 'a.yaml')
      b = write_file('data-us', 'processed', 'b.yml')
      c = write_file('data-us', 'processed', 'list', 'c.yaml')

      expect(eligible_yaml_files(dir)).to eq([a, b, c])
    end

    it 'scans recursively when the direct tiers are empty' do
      dir = make_dir('data-jp', 'sources', 'sanction-lists')
      one = write_file('data-jp', 'sources', 'sanction-lists',
                       'fefta-list', 'entity.yml')
      two = write_file('data-jp', 'sources', 'sanction-lists',
                       'mof-asset-freeze', '01-milosevic', '20260306.yml')

      expect(eligible_yaml_files(dir)).to contain_exactly(one, two)
    end

    it 'excludes deep non-regular entries from the recursive tier' do
      dir = make_dir('data-jp', 'sources', 'sanction-lists')
      deep = write_file('data-jp', 'sources', 'sanction-lists',
                        'list', 'sub', 'entity.yml')
      make_dir('data-jp', 'sources', 'sanction-lists', 'list', 'sub',
               'junk.yaml')

      expect(eligible_yaml_files(dir)).to eq([deep])
    end

    it 'does not scan deeper than one level when direct files exist' do
      dir = make_dir('data-us', 'processed')
      flat = write_file('data-us', 'processed', 'entity.yaml')
      write_file('data-us', 'processed', 'list', 'deep', 'entity.yml')

      expect(eligible_yaml_files(dir)).to eq([flat])
    end

    it 'keeps files reached through a symlinked list directory' do
      dir = make_dir('data-us', 'sources', 'sanction-lists')
      target = write_file('elsewhere', 'entity.yml')
      File.symlink(File.dirname(target), File.join(dir, 'linked'))

      expect(eligible_yaml_files(dir))
        .to eq([File.join(dir, 'linked', 'entity.yml')])
    end

    it 'excludes metadata files at every level' do
      dir = make_dir('data-us', 'sources', 'sanction-lists')
      write_file('data-us', 'sources', 'sanction-lists', '_index.yaml')
      write_file('data-us', 'sources', 'sanction-lists', 'list',
                 '_index.yml')
      eligible = write_file('data-us', 'sources', 'sanction-lists',
                            'list', 'entity.yml')

      expect(eligible_yaml_files(dir)).to contain_exactly(eligible)
    end

    it 'ignores directories named like YAML files' do
      dir = make_dir('data-us', 'processed')
      make_dir('data-us', 'processed', 'not-a-file.yaml')

      expect(eligible_yaml_files(dir)).to eq([])
    end

    it 'returns each file once despite overlapping patterns' do
      dir = make_dir('data-us', 'processed')
      nested = write_file('data-us', 'processed', 'entities', 'a.yaml')

      expect(eligible_yaml_files(dir)).to eq([nested])
    end

    it 'returns an empty array for nil or missing directories' do
      expect(eligible_yaml_files(nil)).to eq([])
      expect(eligible_yaml_files(File.join(sources_dir, 'missing')))
        .to eq([])
    end
  end

  describe '#harmonize_source' do
    it 'feeds deeply nested sanction-list files to transformation' do
      write_file('data-us', 'processed', '_index.yaml')
      write_file('data-us', 'sources', 'sanction-lists', 'sdn-list',
                 '2026', 'entity.yml')

      seen = []
      allow(command).to receive(:transform_data) do |src, _data|
        seen << src
        { entity: nil, entry: nil }
      end

      result = command.send(:harmonize_source, :us)

      expect(result[:status]).to eq(:success)
      expect(seen).to eq([:us])
    end
  end

  # Health-gate behaviour for the same command, scoped here rather than
  # split into a second top-level describe. Needs its own output tree.
  context 'with health gates over a harmonized run' do
    let(:sources_dir) { Dir.mktmpdir('ammitto_gates_sources') }
    let(:output_dir) { Dir.mktmpdir('ammitto_gates_output') }
    let(:options) { { sources_dir: sources_dir, output_dir: output_dir } }

    after do
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
end
