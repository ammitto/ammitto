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

  # @param dir [String] output directory
  # @param names [Array<String>] vessel record files to leave there
  # @return [void]
  def leave_vessels(dir, *names)
    names.each { |name| File.write(File.join(dir, name), "vessel_name: X\nimo_number: '1'\n") }
  end

  # A record of a source's class with every attribute filled in, so the file
  # it writes has the keys a real record has.
  # @param klass [Class] a Lutaml::Model::Serializable subclass
  # @param depth [Integer] nesting already entered
  # @return [Object] the populated instance
  def populated(klass, depth = 0)
    klass.new.tap do |record|
      klass.attributes.each do |name, attribute|
        value = attribute_value(attribute, depth)
        record.public_send("#{name}=", attribute.collection? && value ? [value] : value)
      end
    end
  end

  # @param attribute [Lutaml::Model::Attribute] the attribute to fill
  # @param depth [Integer] nesting already entered
  # @return [Object, nil] a value of the attribute's type
  def attribute_value(attribute, depth)
    type = attribute.type
    return (depth < 2 ? populated(type, depth + 1) : nil) if type.respond_to?(:mappings_for)

    case type.to_s
    when /Integer/ then 1
    when /Float|Decimal/ then 1.5
    when /Boolean/ then true
    when /Date/ then Date.new(2020, 1, 1)
    else 'x1'
    end
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
  # @param source [String] source the index names
  # @param count [Integer] records the previous harvest wrote
  # @param files [Array<String>, nil] the recorded files; omitted when nil
  # @return [void]
  def index_for(dir, source, count, files: nil)
    index = { 'source' => source, 'count' => count }
    index['files'] = files if files
    File.write(File.join(dir, '_index.yaml'), index.to_yaml)
  end

  # @param dir [String] output directory
  # @return [Hash] the index the run wrote
  def index_in(dir)
    YAML.safe_load_file(File.join(dir, '_index.yaml'))
  end

  # @param source [Symbol] source code
  # @param name [Symbol] list attribute named in ITEM_ATTRIBUTES
  # @return [Class] the record class yielded by the list's #items
  def item_type_for(source, name)
    attribute = pruning.send(:source_model_class_for, source).attributes.fetch(name)
    return attribute.type if attribute.collection?

    attribute.type.attributes.fetch(:items).type
  end

  # Put one item in every record collection the list class has, named in
  # ITEM_ATTRIBUTES or not, so #items shows which of them it returns. UN
  # wraps its collections in an object holding them under `items`.
  # @param source [Symbol] source code
  # @return [Object] a source list with one object in every collection
  def list_with_every_collection(source)
    list = pruning.send(:source_model_class_for, source).new
    list.class.attributes.each do |name, attribute|
      if attribute.collection?
        list.public_send("#{name}=", [attribute.type.new]) if attribute.type.respond_to?(:mappings_for)
      elsif attribute.type.respond_to?(:attributes) && attribute.type.attributes[:items]&.collection?
        wrapper = attribute.type.new
        wrapper.items = [attribute.type.attributes[:items].type.new]
        list.public_send("#{name}=", wrapper)
      end
    end
    list
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

  context 'when a delete fails' do
    let(:target) { File.join(dir, 'gbr-delisted.yaml') }

    before do
      previous_harvest(dir, 41, files: [*listed, 'gbr-delisted.yaml'])
      leave_files(dir, *listed, 'gbr-delisted.yaml')
    end

    it 'does not count a file that is already gone' do
      allow(File).to receive(:delete).and_call_original
      allow(File).to receive(:delete).with(target).and_raise(Errno::ENOENT)

      expect(pruning.send(:prune_stale_records, :uk, listed.to_h { |n| [n, []] }, dir)).to be_empty
    end

    it 'reports the source as failed when the file cannot be removed' do
      allow(File).to receive(:delete).and_call_original
      allow(File).to receive(:delete).with(target).and_raise(Errno::EACCES)
      command = described_class.new(thor_options(prune: true, output_dir: dir), ['uk'])
      allow(command).to receive(:fetch_with_source_models) do |source, _extractor, output_dir|
        { code: source, status: :success, count: save(command, uk_records(40), output_dir, source) }
      end

      expect { command.run }
        .to raise_error(Thor::Error, /Fetch failed for: uk/)
        .and output(/0 succeeded, 1 failed.*uk: .*Permission denied/m).to_stdout
      expect(File).to exist(target)
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
      expect(pruning.send(:filename_from_ref, source, 'x1')).to eq("#{prefix}x1.yaml")
    end
  end

  it 'names, for each fetchable source, exactly the list attributes its #items returns' do
    fetchable = Ammitto::Config::Defaults::FETCHABLE_SOURCES
    expect(Ammitto::Cmd::Fetch::StaleRecordPruner::ITEM_ATTRIBUTES.keys).to match_array(fetchable)

    fetchable.each do |source|
      named = Ammitto::Cmd::Fetch::StaleRecordPruner::ITEM_ATTRIBUTES.fetch(source)
      list = list_with_every_collection(source)

      expect(list.items.map(&:class)).to match_array(named.map { |name| item_type_for(source, name) }),
                                         "#{source}: ITEM_ATTRIBUTES differs from #items"
    end
  end

  it 'adopts the file the real writer produces for every record class of every fetchable source' do
    attributes = Ammitto::Cmd::Fetch::StaleRecordPruner::ITEM_ATTRIBUTES
    expect(attributes).not_to be_empty

    attributes.each do |source, names|
      names.each do |name|
        Dir.mktmpdir do |directory|
          item = populated(item_type_for(source, name))
          written = described_class.new(thor_options, [source.to_s])
                                   .send(:write_items, source, [item], directory)
          path = File.join(directory, written.keys.first)

          expect(pruning.send(:record_of_source?, source, path)).to be(true), "#{source}.#{name} not adopted"
        end
      end
    end
  end

  it 'has a prefix entry for every fetchable source' do
    table = Ammitto::Cmd::Fetch::ItemMapper::FILENAME_PREFIXES

    expect(Ammitto::Config::Defaults::FETCHABLE_SOURCES - table.keys).to be_empty
  end

  context 'with --prune over an index that names the source but lists no files' do
    let(:vessel_pruning) { described_class.new(thor_options(prune: true), ['eu_vessels']) }
    let(:written) { { 'eu-vessel-1.yaml' => [] } }

    before do
      index_for(dir, 'eu_vessels', 41)
      leave_vessels(dir, 'eu-vessel-1.yaml', 'eu-vessel-2.yaml')
      leave_files(dir, 'notes.yaml', 'wb-other.yaml')
    end

    it 'removes a prefixed vessel file this run did not write' do
      pruned = vessel_pruning.send(:prune_stale_records, :eu_vessels, written, dir)

      expect(pruned).to eq(['eu-vessel-2.yaml'])
      expect(written_records(dir)).to include('eu-vessel-1.yaml', 'notes.yaml', 'wb-other.yaml')
    end

    it "keeps a prefixed file that is not shaped like this source's record" do
      File.write(File.join(dir, 'eu-vessel-other-shape.yaml'), "entity_type: organization\n")
      File.write(File.join(dir, 'eu-vessel-junk.yaml'), "- just\n- a list\n")
      File.write(File.join(dir, 'eu-vessel-bad.yaml'), "a: [unclosed\n")

      pruned = vessel_pruning.send(:prune_stale_records, :eu_vessels, written, dir)

      expect(pruned).to eq(['eu-vessel-2.yaml'])
      expect(written_records(dir)).to include('eu-vessel-other-shape.yaml', 'eu-vessel-junk.yaml', 'eu-vessel-bad.yaml')
    end

    it 'keeps a prefixed file shaped like a collection #items does not return' do
      index_for(dir, 'ch', 41)
      File.write(File.join(dir, 'ch-program.yaml'), "ssid: '1'\nprogram_keys:\n- p\n")
      File.write(File.join(dir, 'ch-target.yaml'), "ssid: '1'\nentity_type: entity\n")
      ch = described_class.new(thor_options(prune: true), ['ch'])

      pruned = ch.send(:prune_stale_records, :ch, { 'ch-new.yaml' => [] }, dir)

      expect(pruned).to eq(['ch-target.yaml'])
      expect(written_records(dir)).to include('ch-program.yaml')
    end

    it 'does not count a file kept for its shape as left in place' do
      File.write(File.join(dir, 'eu-vessel-other-shape.yaml'), "entity_type: organization\n")

      expect(vessel_pruning.send(:retained_records, :eu_vessels, written, dir)).to eq(['eu-vessel-2.yaml'])
    end

    it 'keeps the file when the index names another source' do
      index_for(dir, 'eu', 41)

      expect(vessel_pruning.send(:prune_stale_records, :eu_vessels, written, dir)).to be_empty
      expect(written_records(dir)).to include('eu-vessel-2.yaml')
    end

    it 'keeps the file when the index changes to another source before the delete' do
      allow(vessel_pruning).to receive(:stale_records).and_wrap_original do |original, *args|
        stale = original.call(*args)
        index_for(dir, 'eu', 41)
        stale
      end

      expect(vessel_pruning.send(:prune_stale_records, :eu_vessels, written, dir)).to be_empty
      expect(written_records(dir)).to include('eu-vessel-2.yaml')
    end

    it 'keeps the file when its content changes to another shape before the delete' do
      allow(vessel_pruning).to receive(:stale_records).and_wrap_original do |original, *args|
        stale = original.call(*args)
        File.write(File.join(dir, 'eu-vessel-2.yaml'), "entity_type: organization\n")
        stale
      end

      expect(vessel_pruning.send(:prune_stale_records, :eu_vessels, written, dir)).to be_empty
      expect(written_records(dir)).to include('eu-vessel-2.yaml')
    end

    it 'leaves the orphans in place and records them when the ceiling refuses' do
      leave_vessels(dir, 'eu-vessel-3.yaml', 'eu-vessel-4.yaml')

      expect { vessel_pruning.send(:prune_stale_records, :eu_vessels, written, dir) }
        .to output(/left 3 files in place/).to_stderr
      expect(vessel_pruning.send(:retained_records, :eu_vessels, written, dir))
        .to eq(%w[eu-vessel-2.yaml eu-vessel-3.yaml eu-vessel-4.yaml])
    end

    it 'still removes a file the index records, whatever its content' do
      index_for(dir, 'eu_vessels', 41, files: ['eu-vessel-1.yaml', 'eu-vessel-old.yaml'])
      leave_files(dir, 'eu-vessel-old.yaml')

      pruned = vessel_pruning.send(:prune_stale_records, :eu_vessels, written, dir)

      expect(pruned).to eq(%w[eu-vessel-2.yaml eu-vessel-old.yaml])
    end
  end

  context 'with --prune over a source whose filenames carry no prefix' do
    it 'adopts and removes a shaped orphan for every empty-prefix source' do
      shapes = {
        uk: { 'unique_id' => 'GBR-orphan' },
        eu: { 'eu_reference_number' => 'EU-orphan' },
        un: { 'reference_number' => 'UN-orphan' },
        us: { 'uid' => 'US-orphan' }
      }

      shapes.each do |source, shape|
        Dir.mktmpdir do |source_dir|
          index_for(source_dir, source.to_s, 41)
          File.write(File.join(source_dir, 'orphan.yaml'), shape.to_yaml)
          command = described_class.new(thor_options(prune: true), [source.to_s])

          pruned = command.send(:prune_stale_records, source,
                                { 'current.yaml' => [] }, source_dir)

          expect(pruned).to eq(['orphan.yaml']), source.to_s
          expect(File).not_to exist(File.join(source_dir, 'orphan.yaml'))
        end
      end
    end

    it 'keeps a non-record YAML file while adopting a shaped orphan' do
      index_for(dir, 'uk', 41)
      File.write(File.join(dir, 'gbr-orphan.yaml'), { 'unique_id' => 'GBR-orphan' }.to_yaml)
      File.write(File.join(dir, 'source.yaml'), { 'source' => 'uk' }.to_yaml)
      File.write(File.join(dir, 'name.yaml'), { 'name' => 'not a record' }.to_yaml)

      pruned = pruning.send(:prune_stale_records, :uk, { 'current.yaml' => [] }, dir)

      expect(pruned).to eq(['gbr-orphan.yaml'])
      expect(written_records(dir)).to include('source.yaml', 'name.yaml')
    end

    it 'does not adopt protected directory entries' do
      index_for(dir, 'uk', 41)
      File.write(File.join(dir, 'gbr-orphan.yaml'), { 'unique_id' => 'GBR-orphan' }.to_yaml)
      File.write(File.join(dir, '.gbr-hidden.yaml'), { 'unique_id' => 'GBR-hidden' }.to_yaml)
      File.write(File.join(dir, '.gitkeep'), '')
      File.write(File.join(dir, 'gbr-not-yaml.txt'), { 'unique_id' => 'GBR-text' }.to_yaml)
      Dir.mkdir(File.join(dir, 'gbr-directory.yaml'))
      Dir.mkdir(File.join(dir, 'gbr-target'))
      File.symlink(File.join(dir, 'gbr-target'), File.join(dir, 'gbr-symlink.yaml'))
      File.write(File.join(dir, '.gbr-file-target.yaml'), { 'unique_id' => 'GBR-file-target' }.to_yaml)
      File.symlink(File.join(dir, '.gbr-file-target.yaml'), File.join(dir, 'gbr-file-symlink.yaml'))

      pruned = pruning.send(:prune_stale_records, :uk, { 'current.yaml' => [] }, dir)

      expect(pruned).to eq(['gbr-orphan.yaml'])
      expect(File).to exist(File.join(dir, '_index.yaml'))
      expect(File).to exist(File.join(dir, '.gbr-hidden.yaml'))
      expect(File).to exist(File.join(dir, '.gitkeep'))
      expect(File).to exist(File.join(dir, 'gbr-not-yaml.txt'))
      expect(File).to exist(File.join(dir, 'gbr-directory.yaml'))
      expect(File).to exist(File.join(dir, 'gbr-symlink.yaml'))
      expect(File).to exist(File.join(dir, 'gbr-file-symlink.yaml'))
      expect(File.symlink?(File.join(dir, 'gbr-symlink.yaml'))).to be(true)
      expect(File.symlink?(File.join(dir, 'gbr-file-symlink.yaml'))).to be(true)
    end

    it 'leaves too many shaped orphans in place and records them' do
      names = %w[gbr-orphan-a.yaml gbr-orphan-b.yaml gbr-orphan-c.yaml]
      index_for(dir, 'uk', 41)
      names.each_with_index do |name, index|
        File.write(File.join(dir, name), { 'unique_id' => "GBR-orphan-#{index}" }.to_yaml)
      end

      expect { save(pruning, uk_records(40), dir) }
        .to output(/left 3 files in place/).to_stderr

      expect(index_in(dir)).to include('left_in_place' => 3,
                                       'left_in_place_files' => names.sort)
      expect(written_records(dir)).to include(*names)
    end

    it 'lets a later --allow-shrink run remove the orphans the ceiling recorded' do
      names = %w[gbr-orphan-a.yaml gbr-orphan-b.yaml gbr-orphan-c.yaml]
      index_for(dir, 'uk', 41)
      names.each_with_index do |name, index|
        File.write(File.join(dir, name), { 'unique_id' => "GBR-orphan-#{index}" }.to_yaml)
      end
      expect { save(pruning, uk_records(40), dir) }.to output.to_stderr

      accepting = described_class.new(thor_options(prune: true, allow_shrink: true), ['uk'])
      save(accepting, uk_records(40), dir)

      expect(written_records(dir)).to match_array(Array.new(40) { |i| "gbr#{i}.yaml" })
      expect(index_in(dir)['files']).to match_array(Array.new(40) { |i| "gbr#{i}.yaml" })
    end

    it 'keeps a shaped orphan through an empty harvest and adopts it on the next one' do
      index_for(dir, 'uk', 41)
      File.write(File.join(dir, 'gbr-orphan.yaml'), { 'unique_id' => 'GBR-orphan' }.to_yaml)

      empty = pruning.send(:prune_stale_records, :uk, {}, dir)
      expect(empty).to be_empty
      expect(written_records(dir)).to include('gbr-orphan.yaml')

      pruned = pruning.send(:prune_stale_records, :uk, { 'current.yaml' => [] }, dir)
      expect(pruned).to eq(['gbr-orphan.yaml'])
    end

    it 'partially prunes shaped orphans within the five percent ceiling' do
      names = %w[gbr-orphan-a.yaml gbr-orphan-b.yaml]
      index_for(dir, 'uk', 41)
      names.each_with_index do |name, index|
        File.write(File.join(dir, name), { 'unique_id' => "GBR-orphan-#{index}" }.to_yaml)
      end

      save(pruning, uk_records(39), dir)

      expect(written_records(dir)).to match_array(Array.new(39) { |i| "gbr#{i}.yaml" })
    end

    it 'keeps a file made only of keys another source shares, or without a string identity' do
      index_for(dir, 'uk', 41)
      File.write(File.join(dir, 'gbr-orphan.yaml'), { 'unique_id' => 'GBR-orphan' }.to_yaml)
      File.write(File.join(dir, 'shared.yaml'), { 'addresses' => [] }.to_yaml)
      File.write(File.join(dir, 'blank.yaml'), { 'unique_id' => ' ', 'addresses' => [] }.to_yaml)
      File.write(File.join(dir, 'wide-blank.yaml'), { 'unique_id' => "\u2003" }.to_yaml)
      { 'false' => false, 'list' => [], 'map' => {}, 'number' => 7 }.each do |name, value|
        File.write(File.join(dir, "#{name}.yaml"), { 'unique_id' => value }.to_yaml)
      end

      pruned = pruning.send(:prune_stale_records, :uk, { 'current.yaml' => [] }, dir)

      expect(pruned).to eq(['gbr-orphan.yaml'])
      expect(written_records(dir)).to include('shared.yaml', 'blank.yaml', 'wide-blank.yaml', 'false.yaml', 'list.yaml',
                                              'map.yaml', 'number.yaml')
    end

    it 'names, for each unprefixed source, the key its records are identified by' do
      Ammitto::Cmd::Fetch::StaleRecordPruner::IDENTITY_KEYS.each do |source, key|
        Ammitto::Cmd::Fetch::StaleRecordPruner::ITEM_ATTRIBUTES.fetch(source).each do |name|
          record = item_type_for(source, name).new(key.to_sym => 'ID-1')
          expect(record.identifier).to eq('ID-1'), "#{source}/#{name}"
          expect(YAML.safe_load(record.to_yaml)).to include(key => 'ID-1')
        end
      end
      unprefixed = Ammitto::Cmd::Fetch::ItemMapper::FILENAME_PREFIXES.select { |_, p| p.empty? }.keys
      expect(Ammitto::Cmd::Fetch::StaleRecordPruner::IDENTITY_KEYS.keys).to match_array(unprefixed)
    end

    it 'keeps a path that became a symlink between the scan and the delete' do
      index_for(dir, 'uk', 41)
      File.write(File.join(dir, '.target.yaml'), { 'unique_id' => 'GBR-target' }.to_yaml)
      File.symlink(File.join(dir, '.target.yaml'), File.join(dir, 'gbr-swapped.yaml'))

      expect(pruning.send(:delete_if_still_owned, :uk, 'gbr-swapped.yaml', dir)).to be(false)
      expect(File.symlink?(File.join(dir, 'gbr-swapped.yaml'))).to be(true)
    end

    it "keeps another source's shaped record under an unprefixed name" do
      index_for(dir, 'uk', 41)
      File.write(File.join(dir, 'gbr-orphan.yaml'), { 'unique_id' => 'GBR-orphan' }.to_yaml)
      File.write(File.join(dir, 'eu-record.yaml'), { 'eu_reference_number' => 'EU-record' }.to_yaml)

      pruned = pruning.send(:prune_stale_records, :uk, { 'current.yaml' => [] }, dir)

      expect(pruned).to eq(['gbr-orphan.yaml'])
      expect(written_records(dir)).to include('eu-record.yaml')
    end

    it "keeps another source's record under that source's prefix, even when its keys fit" do
      index_for(dir, 'un', 41)
      File.write(File.join(dir, 'orphan.yaml'), { 'reference_number' => 'UN-orphan' }.to_yaml)
      File.write(File.join(dir, 'tr-7.yaml'), { 'reference_number' => 'TR-7' }.to_yaml)
      un_pruning = described_class.new(thor_options(prune: true), ['un'])

      pruned = un_pruning.send(:prune_stale_records, :un, { 'current.yaml' => [] }, dir)

      expect(pruned).to eq(['orphan.yaml'])
      expect(written_records(dir)).to include('tr-7.yaml')
      expect(un_pruning.send(:delete_if_still_owned, :un, 'tr-7.yaml', dir)).to be(false)
    end

    it 'still removes a file the index records under a name another prefix starts' do
      index_for(dir, 'un', 41, files: ['tr-7.yaml'])
      File.write(File.join(dir, 'tr-7.yaml'), { 'reference_number' => 'TR-7' }.to_yaml)
      un_pruning = described_class.new(thor_options(prune: true), ['un'])

      pruned = un_pruning.send(:prune_stale_records, :un, { 'current.yaml' => [] }, dir)

      expect(pruned).to eq(['tr-7.yaml'])
    end
  end

  context 'with the prune ceiling on a small previous harvest' do
    let(:small) { Array.new(9) { |i| "gbr#{i}.yaml" } }

    before { leave_files(dir, *small, 'gbr-a.yaml', 'gbr-b.yaml') }

    it 'allows one removal when 5% of the previous harvest rounds to nothing' do
      previous_harvest(dir, 10, files: [*small, 'gbr-a.yaml'])

      pruned = pruning.send(:prune_stale_records, :uk, small.to_h { |n| [n, []] }, dir)

      expect(pruned).to eq(['gbr-a.yaml'])
    end

    it 'still refuses two removals' do
      previous_harvest(dir, 11, files: [*small, 'gbr-a.yaml', 'gbr-b.yaml'])

      expect { pruning.send(:prune_stale_records, :uk, small.to_h { |n| [n, []] }, dir) }
        .to output(/left 2 files in place/).to_stderr
    end
  end

  context 'when the ceiling leaves files in place and the index records it' do
    let(:stale_names) { %w[gbr-b.yaml gbr-a.yaml gbr-c.yaml] }

    before do
      previous_harvest(dir, 43, files: [*listed, *stale_names])
      leave_files(dir, *listed, *stale_names)
    end

    it 'records the count and the sorted names' do
      expect { save(pruning, uk_records(40), dir) }.to output.to_stderr

      expect(index_in(dir)).to include('left_in_place' => 3,
                                       'left_in_place_files' => %w[gbr-a.yaml gbr-b.yaml gbr-c.yaml])
    end

    it 'records nothing when everything stale was removed' do
      previous_harvest(dir, 43, files: [*listed, 'gbr-a.yaml'])
      save(pruning, uk_records(40), dir)

      expect(index_in(dir).keys).not_to include('left_in_place', 'left_in_place_files')
    end

    it 'keeps the four keys without --prune' do
      save(described_class.new(thor_options, ['uk']), uk_records(40), dir)

      expect(index_in(dir).keys).to eq(%w[source count fetched_at schema])
    end

    it 'still succeeds' do
      expect { expect(save(pruning, uk_records(40), dir)).to eq(40) }.to output.to_stderr
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
    # The eu run rewrites _index.yaml under source eu, so uk finds no index
    # of its own and removes nothing, even though it once owned the path.
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
