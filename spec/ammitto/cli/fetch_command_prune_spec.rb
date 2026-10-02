# frozen_string_literal: true

require 'tmpdir'
require 'ammitto'
require 'ammitto/cli'
require 'ammitto/cli/fetch_command'
require 'ammitto/extractors/uk_extractor'

# Helpers for driving save_as_yaml, the step that writes and then prunes.
module StaleRecordPrunerSpecHelpers
  Harvest = Struct.new(:items)

  # @param dir [String] output directory
  # @param names [Array<String>] files to leave there
  # @return [void]
  def leave_files(dir, *names)
    names.each { |name| File.write(File.join(dir, name), "old: true\n") }
  end

  # @param command [Ammitto::Cmd::FetchCommand] the command under test
  # @param records [Array] records the source lists now
  # @param dir [String] output directory
  # @param source [Symbol] source code
  # @return [Integer] files written
  def save(command, records, dir, source = :uk)
    command.send(:save_as_yaml, source, Harvest.new(records), dir)
  end

  # @param dir [String] output directory
  # @return [Hash] the index the run wrote
  def index_in(dir)
    YAML.safe_load_file(File.join(dir, '_index.yaml'))
  end
end

RSpec.describe Ammitto::Cmd::FetchCommand do
  include HarvestFixtures
  include StaleRecordPrunerSpecHelpers

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  let(:dir) { @dir }
  let(:pruning) { described_class.new(thor_options(prune: true), ['uk']) }

  # Forty listed records, one delisted: small enough to sit under the
  # prune ceiling, as a real delisting does.
  let(:listed) { Array.new(40) { |i| "gbr#{i}.yaml" } }

  context 'with --prune over a previous harvest of the same source' do
    before do
      previous_harvest(dir, 41, files: [*listed, 'gbr-delisted.yaml'])
      leave_files(dir, *listed, 'gbr-delisted.yaml')
    end

    it 'removes the file of a record the source no longer lists' do
      save(pruning, uk_records(40), dir)

      expect(written_records(dir)).to match_array(listed)
    end

    it 'records how many files it removed in the index' do
      save(pruning, uk_records(40), dir)

      expect(index_in(dir)).to include('count' => 40, 'pruned' => 1)
    end

    it 'lists the removed files in verbose output' do
      verbose = described_class.new(thor_options(prune: true, verbose: true), ['uk'])

      expect { save(verbose, uk_records(40), dir) }
        .to output(/Pruned 1 files.*\n\s+gbr-delisted\.yaml/).to_stdout
    end

    it 'keeps files that do not end in .yaml' do
      leave_files(dir, 'README.md')
      save(pruning, uk_records(40), dir)

      expect(written_records(dir)).to include('README.md')
    end

    it 'prunes nothing when the harvest is refused' do
      collapsed = uk_records(1)

      expect { save(pruning, collapsed, dir) }.to raise_error(Ammitto::ParseError)
      expect(written_records(dir)).to include('gbr-delisted.yaml')
    end

    it 'prunes nothing from an empty harvest' do
      save(described_class.new(thor_options(prune: true, allow_shrink: true), ['uk']), [], dir)

      expect(written_records(dir)).to include('gbr-delisted.yaml')
    end
  end

  context 'with --prune when the harvest wrote nothing' do
    # The collapse guard refuses an empty harvest unless --allow-shrink.
    let(:pruning) { described_class.new(thor_options(prune: true, allow_shrink: true), ['uk']) }

    before do
      previous_harvest(dir, 41, files: [*listed, 'gbr-delisted.yaml'])
      leave_files(dir, *listed, 'gbr-delisted.yaml')
    end

    it 'keeps the previously owned files listed and deletes nothing' do
      save(pruning, [], dir)

      expect(index_in(dir)).to include('count' => 0, 'files' => [*listed, 'gbr-delisted.yaml'].sort)
      expect(written_records(dir)).to contain_exactly(*listed, 'gbr-delisted.yaml')
    end

    it "records no files when the previous index is not this source's" do
      File.write(File.join(dir, '_index.yaml'),
                 { 'source' => 'eu', 'count' => 3, 'files' => %w[eu-a.yaml] }.to_yaml)
      save(pruning, [], dir)

      expect(index_in(dir)['files']).to eq([])
    end
  end

  context 'when the index changes between the stale scan and the delete' do
    before do
      previous_harvest(dir, 41, files: [*listed, 'gbr-delisted.yaml'])
      leave_files(dir, *listed, 'gbr-delisted.yaml')
    end

    it 'keeps the file when the index now names another source' do
      allow(pruning).to receive(:stale_records).and_wrap_original do |original, *args|
        stale = original.call(*args)
        File.write(File.join(dir, '_index.yaml'),
                   { 'source' => 'eu', 'count' => 1, 'files' => ['gbr-delisted.yaml'] }.to_yaml)
        stale
      end
      written = listed.to_h { |name| [name, []] }

      pruned = pruning.send(:prune_stale_records, :uk, written, dir)

      expect(pruned).to be_empty
      expect(written_records(dir)).to include('gbr-delisted.yaml')
    end

    it 'keeps the file when the index no longer lists it' do
      allow(pruning).to receive(:stale_records).and_wrap_original do |original, *args|
        stale = original.call(*args)
        previous_harvest(dir, 40, files: listed)
        stale
      end
      written = listed.to_h { |name| [name, []] }

      expect(pruning.send(:prune_stale_records, :uk, written, dir)).to be_empty
      expect(written_records(dir)).to include('gbr-delisted.yaml')
    end

    it 'keeps the file when the index now holds files as a bare string' do
      allow(pruning).to receive(:stale_records).and_wrap_original do |original, *args|
        stale = original.call(*args)
        File.write(File.join(dir, '_index.yaml'),
                   { 'source' => 'uk', 'count' => 1, 'files' => 'gbr-delisted.yaml' }.to_yaml)
        stale
      end
      written = listed.to_h { |name| [name, []] }

      pruned = pruning.send(:prune_stale_records, :uk, written, dir)

      expect(pruned).to be_empty
      expect(written_records(dir)).to include('gbr-delisted.yaml')
    end
  end

  context 'when more than the ceiling would go' do
    before do
      previous_harvest(dir, 41, files: [*listed, 'gbr-a.yaml', 'gbr-b.yaml', 'gbr-c.yaml'])
      leave_files(dir, *listed, 'gbr-a.yaml', 'gbr-b.yaml', 'gbr-c.yaml')
    end

    it 'leaves the files in place and says why' do
      expect { save(pruning, uk_records(40), dir) }
        .to output(/left 3 files in place.*--allow-shrink/).to_stderr
      expect(written_records(dir)).to include('gbr-a.yaml', 'gbr-b.yaml', 'gbr-c.yaml')
    end

    it 'removes them when --allow-shrink accepts the drop' do
      accepting = described_class.new(thor_options(prune: true, allow_shrink: true), ['uk'])
      save(accepting, uk_records(40), dir)

      expect(written_records(dir)).to match_array(listed)
    end
  end

  it 'prunes nothing when several sources share --output-dir' do
    previous_harvest(dir, 41, files: [*listed, 'gbr-delisted.yaml'])
    leave_files(dir, *listed, 'gbr-delisted.yaml')
    shared = described_class.new(thor_options(prune: true, output_dir: dir), %w[uk eu])

    expect { save(shared, uk_records(40), dir) }.to output(/--prune skipped/).to_stderr
    expect(written_records(dir)).to include('gbr-delisted.yaml')
  end

  it 'prunes like a single source when the same source is named twice' do
    previous_harvest(dir, 41, files: [*listed, 'gbr-delisted.yaml'])
    leave_files(dir, *listed, 'gbr-delisted.yaml')
    repeated = described_class.new(thor_options(prune: true, output_dir: dir, allow_shrink: true), %w[uk uk])

    expect { save(repeated, uk_records(40), dir) }.not_to output(/--prune skipped/).to_stderr
    expect(written_records(dir)).not_to include('gbr-delisted.yaml')
    expect(index_in(dir)['files']).to match_array(listed)
  end

  it 'prunes nothing for a source whose filenames it does not know' do
    previous_harvest(dir, 41, files: ['gbr-delisted.yaml'])
    leave_files(dir, 'gbr-delisted.yaml')
    previous = pruning.send(:previous_index, :uk, dir)

    expect(pruning.send(:stale_records, :unlisted, { 'gbr0.yaml' => [] }, dir, previous)).to be_empty
  end

  it 'names every prefixed source the way filename_from_ref does' do
    Ammitto::Cmd::Fetch::ItemMapper::FILENAME_PREFIXES.each do |source, prefix|
      expect(pruning.send(:filename_from_ref, source, 'x1')).to start_with(prefix)
    end
  end

  it 'keeps stale files when --prune is not passed' do
    previous_harvest(dir, 2)
    leave_files(dir, 'gbr-delisted.yaml')
    save(described_class.new(thor_options, ['uk']), uk_records(2), dir)

    expect(written_records(dir)).to include('gbr-delisted.yaml')
  end

  it 'prunes nothing in a directory with no previous index' do
    leave_files(dir, 'unrelated.yaml')
    save(pruning, uk_records(2), dir)

    expect(written_records(dir)).to include('unrelated.yaml')
  end

  it "prunes nothing in a directory holding another source's index" do
    File.write(File.join(dir, '_index.yaml'), { 'source' => 'eu', 'count' => 1 }.to_yaml)
    leave_files(dir, 'eu-record.yaml')
    save(pruning, uk_records(2), dir)

    expect(written_records(dir)).to include('eu-record.yaml')
  end

  it "removes only files carrying the source's own prefix" do
    File.write(File.join(dir, '_index.yaml'),
               { 'source' => 'au', 'count' => 40,
                 'files' => %w[au-old.yaml au-new.yaml notes.yaml] }.to_yaml)
    leave_files(dir, 'au-old.yaml', 'notes.yaml')
    written = { 'au-new.yaml' => [] }
    leave_files(dir, 'au-new.yaml')

    pruned = pruning.send(:prune_stale_records, :au, written, dir)

    expect(pruned).to eq(['au-old.yaml'])
  end

  context 'when the directory also holds files another source wrote' do
    # A run of `fetch uk eu --output-dir D` leaves an index naming only eu,
    # and uk's unprefixed files beside it.
    it 'keeps files the previous index does not list as its own' do
      File.write(File.join(dir, '_index.yaml'),
                 { 'source' => 'uk', 'count' => 41, 'files' => ['gbr-delisted.yaml'] }.to_yaml)
      leave_files(dir, *listed, 'gbr-delisted.yaml', 'gbr-other-source.yaml')
      save(pruning, uk_records(40), dir)

      expect(written_records(dir)).to include('gbr-other-source.yaml')
      expect(written_records(dir)).not_to include('gbr-delisted.yaml')
    end

    it 'keeps them when the previous index names another source' do
      File.write(File.join(dir, '_index.yaml'),
                 { 'source' => 'eu', 'count' => 3, 'files' => %w[eu-a.yaml] }.to_yaml)
      leave_files(dir, 'gbr-uk-file.yaml', 'eu-a.yaml')
      save(pruning, uk_records(2), dir)

      expect(written_records(dir)).to include('gbr-uk-file.yaml', 'eu-a.yaml')
    end
  end

  context 'when the ceiling leaves delisted files in place' do
    let(:stale_names) { %w[gbr-a.yaml gbr-b.yaml gbr-c.yaml] }
    let(:accepting) { described_class.new(thor_options(prune: true, allow_shrink: true), ['uk']) }

    before do
      previous_harvest(dir, 43, files: [*listed, *stale_names])
      leave_files(dir, *listed, *stale_names)
    end

    it 'keeps them recorded as owned in the new index' do
      expect { save(pruning, uk_records(40), dir) }.to output(/left 3 files in place/).to_stderr

      expect(index_in(dir)).to include('pruned' => 0, 'files' => [*listed, *stale_names].sort)
    end

    it 'lets a later --allow-shrink run remove them' do
      expect { save(pruning, uk_records(40), dir) }.to output.to_stderr
      save(accepting, uk_records(40), dir)

      expect(written_records(dir)).to match_array(listed)
    end

    it 'does not record a file that was removed' do
      save(accepting, uk_records(40), dir)

      expect(index_in(dir)['files']).to eq(listed.sort)
    end

    it 'does not record an owned file that no longer exists' do
      previous_harvest(dir, 44, files: [*listed, *stale_names, 'gbr-gone.yaml'])
      expect { save(pruning, uk_records(40), dir) }.to output.to_stderr

      expect(index_in(dir)['files']).not_to include('gbr-gone.yaml')
    end
  end

  context 'when another source later writes a path this source once owned' do
    # Codex round 3 claimed the prior index would let a uk --prune run
    # delete eu's file. The eu run rewrites _index.yaml under source eu, so
    # uk finds no index of its own and removes nothing.
    it 'keeps that source file when this source runs alone with --prune' do
      save(pruning, uk_records(40), dir)
      expect(index_in(dir)['files']).to include('gbr0.yaml')

      eu = described_class.new(thor_options, ['eu'])
      save(eu, uk_records(40), dir, :eu)
      expect(index_in(dir)).to include('source' => 'eu')

      save(pruning, uk_records(40).drop(1), dir)

      expect(written_records(dir)).to include('gbr0.yaml')
      expect(index_in(dir)).to include('source' => 'uk', 'pruned' => 0)
    end
  end

  context 'with --prune over an index that has no files list' do
    before do
      previous_harvest(dir, 41)
      leave_files(dir, *listed, 'gbr-delisted.yaml')
    end

    it 'removes nothing' do
      save(pruning, uk_records(40), dir)

      expect(written_records(dir)).to include('gbr-delisted.yaml')
    end

    it 'records the files it wrote so the next run can prune' do
      save(pruning, uk_records(40), dir)

      expect(index_in(dir)).to include('pruned' => 0, 'files' => listed.sort)
    end
  end

  context 'without --prune' do
    let(:plain) { described_class.new(thor_options(verbose: true), ['uk']) }

    it 'writes an index with neither files nor pruned' do
      previous_harvest(dir, 2, files: ['gbr-delisted.yaml'])
      save(described_class.new(thor_options, ['uk']), uk_records(2), dir)

      expect(index_in(dir).keys).to eq(%w[source count fetched_at schema])
    end

    it 'prints no pruning line' do
      expect { save(plain, uk_records(2), dir) }
        .to output(/\A\[uk\] Saved 2 files to \S+\n\z/).to_stdout
    end
  end

  context 'with --prune on a route that does not prune' do
    let(:extractor) { instance_double(Ammitto::Extractors::UkExtractor, run: { code: :uk, status: :success, entities: 1 }) }

    before do
      allow(Ammitto::Extractors::UkExtractor).to receive(:new).and_return(extractor)
      leave_files(dir, 'gbr-old.yaml')
    end

    it 'refuses --format jsonld as an error and never runs the extractor' do
      command = described_class.new(thor_options(prune: true, format: 'jsonld', output_dir: dir), ['uk'])

      result = command.send(:fetch_source, :uk)

      expect(result).to include(code: :uk, status: :error)
      expect(result[:error]).to match(/--prune applies only to --format yaml/)
      expect(extractor).not_to have_received(:run)
      expect(Dir.children(dir)).to eq(['gbr-old.yaml'])
    end

    it 'leaves --format jsonld alone without --prune' do
      command = described_class.new(thor_options(format: 'jsonld', output_dir: dir), ['uk'])

      expect(command.send(:fetch_source, :uk)).to include(status: :success)
      expect(extractor).to have_received(:run)
    end
  end
end
