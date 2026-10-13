# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'tmpdir'
require 'ammitto/serialization/json_ld_graph_exporter'

# A rebuild into a reused output directory must replace what it owns. Before
# this, a record removed upstream kept its node files, and the entry still
# declared status active, so a consumer holding the node URL was served a
# sanction that no longer exists.
module GraphStaleNodesSpecHelpers
  def node_path(kind, *parts)
    File.join(output_dir, 'node', kind, *parts)
  end

  def export_run(records, combine: true)
    exporter = described_class.new(output_dir: output_dir, combine: combine)
    records.each do |source, ref, list|
      list ||= 'sanctions'
      exporter.add_node(
        entity: { '@id' => "https://www.ammitto.org/entity/#{source}/#{ref}",
                  '@type' => 'PersonEntity', 'entityType' => 'person',
                  'names' => [{ 'fullName' => ref }] },
        entry: { '@id' => "https://www.ammitto.org/entry/#{source}/#{list}/#{ref}",
                 'entityId' => "https://www.ammitto.org/entity/#{source}/#{ref}",
                 'status' => 'active' },
        source: source
      )
    end
    yield exporter if block_given?
    exporter.export
    exporter
  end
end

RSpec.describe Ammitto::Serialization::JsonLdGraphExporter do
  include GraphStaleNodesSpecHelpers

  let(:output_dir) { Dir.mktmpdir('ammitto_stale_nodes') }

  after { FileUtils.rm_rf(output_dir) }

  it 'removes the entity and entry nodes of a record dropped between runs' do
    export_run([%w[un old], %w[un new]])
    expect(File.exist?(node_path('entity', 'un', 'old.jsonld'))).to be(true)

    export_run([%w[un new]])

    expect(File.exist?(node_path('entity', 'un', 'old.jsonld'))).to be(false)
    expect(File.exist?(node_path('entry', 'un', 'sanctions', 'old.jsonld'))).to be(false)
    expect(File.exist?(node_path('entity', 'un', 'new.jsonld'))).to be(true)
    expect(File.exist?(node_path('entry', 'un', 'sanctions', 'new.jsonld'))).to be(true)
  end

  it 'drops a list directory, and its by-list slice, once the list is gone' do
    export_run([%w[un old gone], %w[un new]])
    export_run([%w[un new]])

    expect(Dir.exist?(node_path('entry', 'un', 'gone'))).to be(false)
    expect(File.exist?(File.join(output_dir, 'by-list', 'un', 'gone.jsonld'))).to be(false)
  end

  it 'leaves the other sources alone when one source is rebuilt' do
    export_run([%w[un old], %w[us keep]])
    export_run([%w[un new]])

    expect(File.exist?(node_path('entity', 'un', 'old.jsonld'))).to be(false)
    expect(File.exist?(node_path('entity', 'us', 'keep.jsonld'))).to be(true)
    expect(File.exist?(node_path('entry', 'us', 'sanctions', 'keep.jsonld'))).to be(true)
  end

  it 'keeps what a source published before when the run carries nothing for it' do
    export_run([%w[un old]])
    export_run([%w[us other]])

    expect(File.exist?(node_path('entity', 'un', 'old.jsonld'))).to be(true)
  end

  it 'leaves a held back source alone' do
    export_run([%w[un old], %w[un new]])
    export_run([%w[un new]]) { |exporter| exporter.hold_back(:un) }

    expect(File.exist?(node_path('entity', 'un', 'old.jsonld'))).to be(true)
  end

  it 'does not delete anything when the export fails part way' do
    export_run([%w[un old], %w[un new]])

    failing = described_class.new(output_dir: output_dir)
    failing.add_node(
      entity: { '@id' => 'https://www.ammitto.org/entity/un/new', 'entityType' => 'person' },
      entry: { '@id' => 'https://www.ammitto.org/entry/un/sanctions/new', 'status' => 'active' },
      source: :un
    )
    allow(failing).to receive(:export_stats).and_raise(Errno::ENOSPC)

    expect { failing.export }.to raise_error(Errno::ENOSPC)
    expect(File.exist?(node_path('entity', 'un', 'old.jsonld'))).to be(true)
  end

  %w[node node/group node/group/un].each do |relative_dir|
    it "preserves files behind a symlinked #{relative_dir} directory" do
      Dir.mktmpdir('ammitto_external_nodes') do |external_dir|
        target = File.join(external_dir, relative_dir)
        source_dir = File.join(external_dir, 'node', 'group', 'un')
        FileUtils.mkdir_p(source_dir)
        victim = File.join(source_dir, 'unrelated.txt')
        File.write(victim, 'preserve')
        link = File.join(output_dir, relative_dir)
        FileUtils.mkdir_p(File.dirname(link))
        File.symlink(target, link)

        export_run([%w[un new]], combine: false)

        expect(File.read(victim)).to eq('preserve')
        expect(File.symlink?(link)).to be(true)
      end
    end
  end

  it 'prunes stale files when the configured output root is a symlink' do
    Dir.mktmpdir('ammitto_output_alias') do |alias_dir|
      root_alias = File.join(alias_dir, 'api')
      File.symlink(output_dir, root_alias)
      export_run([%w[un old]])
      exporter = described_class.new(output_dir: root_alias, combine: false)
      exporter.add_node(
        entity: { '@id' => 'https://www.ammitto.org/entity/un/new', 'entityType' => 'person' },
        entry: { '@id' => 'https://www.ammitto.org/entry/un/sanctions/new', 'status' => 'active' },
        source: :un
      )

      exporter.export

      expect(File.exist?(node_path('entity', 'un', 'old.jsonld'))).to be(false)
      expect(File.exist?(node_path('entity', 'un', 'new.jsonld'))).to be(true)
      expect(File.symlink?(root_alias)).to be(true)
    end
  end

  it 'removes a stale nested symlink without deleting its target' do
    Dir.mktmpdir('ammitto_external_leaf') do |external_dir|
      victim = File.join(external_dir, 'unrelated.txt')
      File.write(victim, 'preserve')
      source_dir = node_path('group', 'un')
      FileUtils.mkdir_p(source_dir)
      link = File.join(source_dir, 'external')
      File.symlink(external_dir, link)

      export_run([%w[un new]], combine: false)

      expect(File.read(victim)).to eq('preserve')
      expect(File.symlink?(link)).to be(false)
    end
  end

  it 'produces the same tree as a fresh export of the same records' do
    records = [%w[un new], %w[us keep]]
    export_run([%w[un old], %w[un new], %w[us keep], %w[us dropped]])
    export_run(records)

    fresh_dir = Dir.mktmpdir('ammitto_stale_fresh')
    begin
      fresh = described_class.new(output_dir: fresh_dir)
      records.each do |source, ref|
        fresh.add_node(
          entity: { '@id' => "https://www.ammitto.org/entity/#{source}/#{ref}",
                    '@type' => 'PersonEntity', 'entityType' => 'person',
                    'names' => [{ 'fullName' => ref }] },
          entry: { '@id' => "https://www.ammitto.org/entry/#{source}/sanctions/#{ref}",
                   'entityId' => "https://www.ammitto.org/entity/#{source}/#{ref}",
                   'status' => 'active' },
          source: source
        )
      end
      fresh.export

      listing = ->(dir) { Dir.glob('node/**/*', base: dir).select { |f| File.file?(File.join(dir, f)) }.sort }
      expect(listing.call(output_dir)).to eq(listing.call(fresh_dir))
    ensure
      FileUtils.rm_rf(fresh_dir)
    end
  end

  [nil, false, {}, { '@id' => '' }, { '@id' => 42 },
   { '@id' => 'urn:example:entity' },
   { '@id' => 'https://www.ammitto.org/entity/us/wrong-source' }].each do |entity|
    it "retains prior nodes when public input has an unexportable entity #{entity.inspect}" do
      export_run([%w[un old]])
      exporter = export_run([%w[un new]]) do |current|
        current.add_node(entity: entity,
                         entry: { '@id' => 'https://www.ammitto.org/entry/un/sanctions/bad' }, source: :un)
      end

      expect(File.exist?(node_path('entity', 'un', 'old.jsonld'))).to be(true)
      expect(exporter.entities).not_to include(nil)
    end
  end

  it 'defers cleanup until the caller has completed its remaining outputs' do
    export_run([%w[un old]])
    exporter = described_class.new(output_dir: output_dir, combine: false)
    exporter.add_node(entity: { '@id' => 'https://www.ammitto.org/entity/un/new' },
                      entry: { '@id' => 'https://www.ammitto.org/entry/un/sanctions/new' }, source: :un)

    exporter.export(cleanup: false)
    expect(File.exist?(node_path('entity', 'un', 'old.jsonld'))).to be(true)
    exporter.cleanup_stale_nodes
    expect(File.exist?(node_path('entity', 'un', 'old.jsonld'))).to be(false)
  end

  it 'does not grant cleanup before an export or after a failed export' do
    export_run([%w[un old]])
    exporter = described_class.new(output_dir: output_dir, combine: false)
    exporter.add_node(entity: { '@id' => 'https://www.ammitto.org/entity/un/new' },
                      entry: { '@id' => 'https://www.ammitto.org/entry/un/sanctions/new' }, source: :un)
    exporter.cleanup_stale_nodes
    expect(File.exist?(node_path('entity', 'un', 'old.jsonld'))).to be(true)
    allow(exporter).to receive(:export_stats).and_raise(Errno::ENOSPC)
    expect { exporter.export(cleanup: false) }.to raise_error(Errno::ENOSPC)
    exporter.cleanup_stale_nodes
    expect(File.exist?(node_path('entity', 'un', 'old.jsonld'))).to be(true)
  end

  { 'document_types' => 'document-types.yml', 'organizations' => 'organizations.yml' }.each do |kind, filename|
    [nil, false, [], {}, { kind => nil }, { kind => 'invalid' },
     { kind => [{ 'id' => 'un/new' }, nil] },
     { kind => [{ 'id' => 'un/new' }, { 'id' => '' }] },
     { kind => [{ 'id' => 'un/new' }, { 'id' => 42 }] }].each do |input|
      it "retains stale #{kind} nodes after incomplete supporting input #{input.inspect}" do
        Dir.mktmpdir do |support|
          path = File.join(support, filename)
          File.write(path, { kind => [{ 'id' => 'un/old' }] }.to_yaml)
          export_run([%w[un old]])
          first = described_class.new(output_dir: output_dir, supporting_dir: support, combine: false)
          first.export
          victim = node_path(kind == 'document_types' ? 'document-type' : 'organization', 'un', 'old.jsonld')
          expect(File.exist?(victim)).to be(true)
          File.write(path, input.to_yaml)
          expect do
            incomplete = described_class.new(output_dir: output_dir, supporting_dir: support, combine: false)
            incomplete.add_node(entity: { '@id' => 'https://www.ammitto.org/entity/un/new' },
                                entry: { '@id' => 'https://www.ammitto.org/entry/un/sanctions/new' }, source: :un)
            incomplete.export
          end.to output(/Warning/).to_stderr
          expect(File.exist?(victim)).to be(true)
        end
      end
    end

    it "allows a valid explicit empty #{kind} array to remove old supporting nodes" do
      Dir.mktmpdir do |support|
        path = File.join(support, filename)
        File.write(path, { kind => [{ 'id' => 'un/old' }] }.to_yaml)
        first = described_class.new(output_dir: output_dir, supporting_dir: support, combine: false)
        first.export
        File.write(path, { kind => [] }.to_yaml)
        current = described_class.new(output_dir: output_dir, supporting_dir: support, combine: false)
        current.add_node(entity: { '@id' => 'https://www.ammitto.org/entity/un/new' },
                         entry: { '@id' => 'https://www.ammitto.org/entry/un/sanctions/new' }, source: :un)
        current.export
        victim = node_path(kind == 'document_types' ? 'document-type' : 'organization', 'un', 'old.jsonld')
        expect(File.exist?(victim)).to be(false)
      end
    end
  end

  [nil, false, [], {}, { 'id' => nil }, { 'id' => false }, { 'id' => 42 }, { 'id' => '' }, '{{{ not yaml: ['].each do |input|
    it "retains prior nodes after incomplete instrument input #{input.inspect}" do
      export_run([%w[un old]])
      Dir.mktmpdir do |instruments|
        File.write(File.join(instruments, 'instrument.yml'), input.is_a?(String) ? input : input.to_yaml)
        expect do
          exporter = described_class.new(output_dir: output_dir, instruments_dir: instruments, combine: false)
          exporter.add_node(entity: { '@id' => 'https://www.ammitto.org/entity/un/new' },
                            entry: { '@id' => 'https://www.ammitto.org/entry/un/sanctions/new' }, source: :un)
          exporter.export
        end.to output(/Warning/).to_stderr
        expect(File.exist?(node_path('entity', 'un', 'old.jsonld'))).to be(true)
      end
    end
  end

  it 'retains prior nodes when an explicitly requested supporting directory is missing' do
    export_run([%w[un old]])
    exporter = described_class.new(output_dir: output_dir, supporting_dir: File.join(output_dir, 'missing'), combine: false)
    exporter.add_node(entity: { '@id' => 'https://www.ammitto.org/entity/un/new' },
                      entry: { '@id' => 'https://www.ammitto.org/entry/un/sanctions/new' }, source: :un)
    exporter.export
    expect(File.exist?(node_path('entity', 'un', 'old.jsonld'))).to be(true)
  end

  it 'still allows deletion when duplicate supporting identifiers use the documented first winner' do
    export_run([%w[un old]])
    Dir.mktmpdir do |support|
      File.write(File.join(support, 'document-types.yml'),
                 { 'document_types' => [{ 'id' => 'un/type' }, { 'id' => 'un/type' }] }.to_yaml)
      expect do
        exporter = described_class.new(output_dir: output_dir, supporting_dir: support, combine: false)
        exporter.add_node(entity: { '@id' => 'https://www.ammitto.org/entity/un/new' },
                          entry: { '@id' => 'https://www.ammitto.org/entry/un/sanctions/new' }, source: :un)
        exporter.export
      end.to output(/ignoring the duplicate/).to_stderr
      expect(File.exist?(node_path('entity', 'un', 'old.jsonld'))).to be(false)
    end
  end

  %w[entity entry].each do |kind|
    ["\n", ' ', "\t", "valid\n", "valid\x01"].each do |tail|
      it "withholds cleanup for an unexportable #{kind} tail #{tail.inspect}" do
        export_run([%w[un old]])
        exporter = described_class.new(output_dir: output_dir, combine: false)
        entity = { '@id' => 'https://www.ammitto.org/entity/un/new' }
        entry = { '@id' => 'https://www.ammitto.org/entry/un/sanctions/new' }
        node = kind == 'entity' ? entity : entry
        node['@id'] = node['@id'].delete_suffix('new') + tail
        expect(exporter.exportable_pair?(entity, entry, 'un')).to be_falsey
        exporter.add_node(entity: entity, entry: entry, source: :un)
        begin
          exporter.export
        rescue Errno::EINVAL
          # Windows rejects these filenames before cleanup; prior nodes
          # must survive whether the graph write succeeds or raises.
          raise unless Gem.win_platform? && ["\t", "valid\x01"].include?(tail)
        end
        expect(File.exist?(node_path('entity', 'un', 'old.jsonld'))).to be(true)
      end
    end
  end

  %i[instruments supporting].each do |kind|
    [0, 0o600, 0o100].each do |mode|
      %w[root nested].each do |depth|
        it "retains prior nodes when #{kind} #{depth} discovery lacks access #{mode}" do
          export_run([%w[un old]])
          Dir.mktmpdir do |input|
            blocked = depth == 'root' ? input : File.join(input, 'nested')
            FileUtils.mkdir_p(blocked)
            File.write(File.join(blocked, 'law.yml'), { 'id' => 'un/law' }.to_yaml)
            File.chmod(mode, blocked)
            begin
              skip 'Filesystem does not deny directory read/search access with chmod' if
                File.readable?(blocked) && File.executable?(blocked)
              expect do
                exporter = described_class.new(output_dir: output_dir, combine: false,
                                               "#{kind}_dir": input)
                exporter.add_node(entity: { '@id' => 'https://www.ammitto.org/entity/un/new' },
                                  entry: { '@id' => 'https://www.ammitto.org/entry/un/sanctions/new' }, source: :un)
                exporter.export
              end.to output(/Warning/).to_stderr
              expect(File.exist?(node_path('entity', 'un', 'old.jsonld'))).to be(true)
            ensure
              File.chmod(0o700, blocked)
            end
          end
        end
      end
    end

    %w[root nested].each do |depth|
      %i[stat children].each do |operation|
        it "retains prior nodes after denied #{operation} inspection of #{kind} #{depth}" do
          export_run([%w[un old]])
          Dir.mktmpdir do |input|
            blocked = depth == 'root' ? input : File.join(input, 'nested')
            FileUtils.mkdir_p(blocked)
            File.write(File.join(blocked, 'law.yml'), { 'id' => 'un/law' }.to_yaml)
            filesystem = operation == :stat ? File : Dir
            allow(filesystem).to receive(operation).and_call_original
            allow(filesystem).to receive(operation).with(blocked).and_raise(Errno::EACCES)

            expect do
              exporter = described_class.new(output_dir: output_dir, combine: false, "#{kind}_dir": input)
              exporter.add_node(entity: { '@id' => 'https://www.ammitto.org/entity/un/new' },
                                entry: { '@id' => 'https://www.ammitto.org/entry/un/sanctions/new' }, source: :un)
              exporter.export
            end.to output(/Warning/).to_stderr
            expect(File.exist?(node_path('entity', 'un', 'old.jsonld'))).to be(true)
            expect(File.exist?(node_path('entry', 'un', 'sanctions', 'old.jsonld'))).to be(true)
          end
        end
      end
    end
  end
end
