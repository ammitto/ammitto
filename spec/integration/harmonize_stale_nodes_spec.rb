# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'json'
require 'ammitto/cli'
require 'ammitto/cli/harmonize_command'

# Real harmonize runs into one reused api/v1 directory. A record removed from
# a source between two runs must not stay published, and the second run must
# leave exactly what a fresh run over the remaining records leaves.
module HarmonizeStaleNodesSpecHelpers
  def write_eu(dir, ids)
    processed = File.join(dir, 'data-eu', 'processed')
    FileUtils.rm_rf(processed)
    FileUtils.mkdir_p(processed)
    ids.each do |id|
      model = Ammitto::Sources::Eu::SanctionEntity.from_yaml({
        'logical_id' => id, 'eu_reference_number' => "EU.#{id}",
        'subject_type' => { 'code' => 'person' },
        'name_aliases' => [{ 'whole_name' => "Person #{id}" }]
      }.to_yaml)
      File.write(File.join(processed, "eu-#{id}.yaml"), model.to_yaml)
    end
  end

  def write_ch(dir, ids)
    processed = File.join(dir, 'data-ch', 'processed')
    FileUtils.rm_rf(processed)
    FileUtils.mkdir_p(processed)
    ids.each do |id|
      model = Ammitto::Sources::Ch::Identity.from_yaml({
        'ssid' => id,
        'names' => [{ 'name_parts' => [
          { 'name_part_type' => 'given-name', 'value' => "Given#{id}" },
          { 'name_part_type' => 'family-name', 'value' => 'Testov' }
        ] }]
      }.to_yaml)
      File.write(File.join(processed, "ch-#{id}.yaml"), model.to_yaml)
    end
  end

  def harmonize(sources_dir, api)
    Ammitto::Cmd::HarmonizeCommand.new(
      { sources_dir: sources_dir, output_dir: api }, %w[eu ch].select { |code| Dir.exist?(File.join(sources_dir, "data-#{code}")) }
    ).run
  end

  # Parsed, without the run's own timestamps: two runs never agree on those
  def content(api, file)
    text = File.read(File.join(api, file))
    return text unless file.end_with?('.json', '.jsonld')

    strip_timestamps(JSON.parse(text))
  end

  def strip_timestamps(value)
    case value
    when Hash then value.reject { |k, _| k.to_s.match?(/generated/i) }.transform_values { |v| strip_timestamps(v) }
    when Array then value.map { |v| strip_timestamps(v) }
    else value
    end
  end

  def tree(api)
    Dir.glob('**/*', base: api).select { |f| File.file?(File.join(api, f)) }.sort
  end
end

RSpec.describe 'harmonize into a reused output directory (integration)' do
  include HarmonizeStaleNodesSpecHelpers

  around do |example|
    Dir.mktmpdir { |dir| (@workdir = dir) && example.run }
  end

  it 'leaves the tree a fresh export of the remaining records leaves' do
    api = File.join(@workdir, 'reused', 'api', 'v1')
    write_eu(@workdir, %w[55 56])
    write_ch(@workdir, %w[111 112])
    harmonize(@workdir, api)
    removed = tree(api).grep(%r{\Anode/(entity|entry)/(eu/.*eu56|ch/.*ch.*112)}i)
    expect(removed).not_to be_empty

    write_eu(@workdir, %w[55])
    write_ch(@workdir, %w[111])
    harmonize(@workdir, api)

    fresh_api = File.join(@workdir, 'fresh', 'api', 'v1')
    harmonize(@workdir, fresh_api)

    expect(tree(api)).to eq(tree(fresh_api))
    expect(removed.select { |f| File.exist?(File.join(api, f)) }).to be_empty
    tree(api).each do |file|
      expect(content(api, file)).to eq(content(fresh_api, file)), file
    end
  end

  it 'keeps a source\'s published nodes when one of its files fails to transform' do
    api = File.join(@workdir, 'reused', 'api', 'v1')
    write_ch(@workdir, %w[111 112])
    harmonize(@workdir, api)
    published = tree(api).grep(%r{\Anode/(entity|entry)/ch/.*112})
    expect(published).not_to be_empty

    File.write(File.join(@workdir, 'data-ch', 'processed', 'ch-112.yaml'), '{{{ not yaml: [')
    expect { harmonize(@workdir, api) }.to raise_error(Thor::Error, /health gate/)

    expect(published.select { |f| File.exist?(File.join(api, f)) }).to eq(published)
  end

  ['', 'false'].each do |yaml|
    it "retains prior source nodes when a previously published input becomes #{yaml.inspect}" do
      api = File.join(@workdir, 'api')
      write_ch(@workdir, %w[111 112])
      harmonize(@workdir, api)
      published = tree(api).grep(%r{\Anode/(entity|entry)/ch/.*112})
      File.write(File.join(@workdir, 'data-ch', 'processed', 'ch-112.yaml'), yaml)

      expect { harmonize(@workdir, api) }.to raise_error(Thor::Error, /no record/)
      expect(published.select { |path| File.exist?(File.join(api, path)) }).to eq(published)
    end
  end

  %i[aggregate search ontology manifest report quality exempted_quality].each do |failure|
    it "retains stale nodes when #{failure} fails after ingestion" do
      api = File.join(@workdir, 'api')
      write_ch(@workdir, %w[111 112])
      write_eu(@workdir, %w[55])
      harmonize(@workdir, api)
      published = tree(api).grep(%r{\Anode/(entity|entry)/ch/.*112})
      write_ch(@workdir, %w[111])
      options = { sources_dir: @workdir, output_dir: api }
      options[:report] = File.join(@workdir, 'report.json') if failure == :report
      options[:allow_empty] = 'ch' if failure == :exempted_quality
      command = Ammitto::Cmd::HarmonizeCommand.new(options, %w[ch eu])
      case failure
      when :aggregate
        allow(command).to receive(:write_source_aggregate).and_wrap_original do |original, source, graph|
          raise Errno::ENOSPC if source == :ch

          original.call(source, graph)
        end
      when :search
        indexer = Ammitto::Serialization::SearchIndexExporter.new
        allow(Ammitto::Serialization::SearchIndexExporter).to receive(:new).and_return(indexer)
        allow(indexer).to receive(:export).and_raise(Errno::ENOSPC)
      when :ontology
        ontology = Ammitto::Serialization::OntologyExporter.new
        allow(Ammitto::Serialization::OntologyExporter).to receive(:new).and_return(ontology)
        allow(ontology).to receive(:export).and_raise(Errno::ENOSPC)
      when :manifest
        allow(Ammitto::Serialization::JsonLdGraphExporter).to receive(:new).and_wrap_original do |original, **args|
          exporter = original.call(**args)
          allow(exporter).to receive(:export_manifest).and_raise(Errno::ENOSPC)
          exporter
        end
      when :report
        allow(command).to receive(:write_report).and_return('report write failed')
      when :quality, :exempted_quality
        allow(command).to receive(:aggregate_name_metrics).and_wrap_original do |original, code, dir|
          code == :ch ? { entity_nodes: 1, named_entities: 0, named_entity_ratio: 0.0 } : original.call(code, dir)
        end
      end

      if failure == :exempted_quality
        expect { command.run }.not_to raise_error
      else
        expect { command.run }.to raise_error(StandardError)
      end
      expect(published.select { |path| File.exist?(File.join(api, path)) }).to eq(published)
    end
  end

  [0, 0o600, 0o100].each do |mode|
    it "retains source nodes when a nested input directory lacks access #{mode}" do
      api = File.join(@workdir, 'api')
      write_ch(@workdir, %w[111 112])
      nested = File.join(@workdir, 'data-ch', 'processed', 'nested')
      FileUtils.mkdir_p(nested)
      FileUtils.mv(File.join(@workdir, 'data-ch', 'processed', 'ch-112.yaml'), File.join(nested, 'ch-112.yaml'))
      harmonize(@workdir, api)
      published = tree(api).grep(%r{\Anode/(entity|entry)/ch/.*112})
      File.chmod(mode, nested)
      begin
        skip 'Filesystem does not deny directory read/search access with chmod' if
          File.readable?(nested) && File.executable?(nested)
        expect { harmonize(@workdir, api) }.to raise_error(Thor::Error, /health gate/)
        expect(published.select { |path| File.exist?(File.join(api, path)) }).to eq(published)
      ensure
        File.chmod(0o700, nested)
      end
    end
  end

  %i[warn silent raise].each do |mode|
    it "retains source nodes after observed parse loss in #{mode} mode" do
      original_mode = Ammitto.configuration.parse_failure_mode
      Ammitto.configure { |config| config.parse_failure_mode = mode }
      begin
        api = File.join(@workdir, 'api')
        input = File.join(@workdir, 'data-tr', 'processed')
        FileUtils.mkdir_p(input)
        write = lambda do |ref, date|
          File.write(File.join(input, "#{ref}.yaml"), {
            'name' => ref, 'entity_type' => 'organization',
            'program' => 'Law No. 7262, Articles 3.A/3.B',
            'listed_date' => date, 'reference_number' => ref
          }.to_yaml)
        end
        write.call('old', '2024-01-01')
        write.call('keep', '2024-01-01')
        build = -> { Ammitto::Cmd::HarmonizeCommand.new({ sources_dir: @workdir, output_dir: api }, ['tr']) }
        build.call.run
        published = tree(api).grep(%r{\Anode/(entity|entry)/tr/.*old})
        expect(published).not_to be_empty
        File.delete(File.join(input, 'old.yaml'))
        write.call('keep', 'not a date')
        command = build.call
        if mode == :raise
          expect { command.run }.to raise_error(Thor::Error, /health gate/)
        else
          expect { command.run }.not_to raise_error
        end
        expect(published.select { |path| File.exist?(File.join(api, path)) }).to eq(published)
      ensure
        Ammitto.configure { |config| config.parse_failure_mode = original_mode }
      end
    end
  end

  %w[root nested].each do |depth|
    %i[stat children].each do |operation|
      it "retains source nodes after denied #{operation} inspection of #{depth} input" do
        api = File.join(@workdir, 'api')
        write_ch(@workdir, %w[111 112])
        write_eu(@workdir, %w[55])
        processed = File.join(@workdir, 'data-ch', 'processed')
        nested = File.join(processed, 'nested')
        FileUtils.mkdir_p(nested)
        FileUtils.mv(File.join(processed, 'ch-112.yaml'), File.join(nested, 'ch-112.yaml'))
        harmonize(@workdir, api)
        published = tree(api).grep(%r{\Anode/(entity|entry)/ch/.*112})
        expect(published).not_to be_empty
        blocked = depth == 'root' ? processed : nested
        filesystem = operation == :stat ? File : Dir
        allow(filesystem).to receive(operation).and_call_original
        allow(filesystem).to receive(operation).with(blocked).and_raise(Errno::EACCES)

        expect { harmonize(@workdir, api) }.to raise_error(Thor::Error, /health gate/)
        expect(published.select { |path| File.exist?(File.join(api, path)) }).to eq(published)
      end
    end
  end
end
