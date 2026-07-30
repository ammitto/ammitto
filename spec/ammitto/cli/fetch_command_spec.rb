# frozen_string_literal: true

require 'ammitto'
require 'ammitto/cli'
require 'ammitto/cli/fetch_command'

RSpec.describe Ammitto::Cmd::FetchCommand do
  it 'reports CN as manually managed instead of a silent extractor success' do
    cmd = described_class.new({}, ['cn'])
    result = cmd.send(:fetch_source, :cn)

    expect(result[:status]).to eq(:error)
    expect(result[:error]).to match(/manually managed in data-cn/)
  end

  it 'requires sources or --all' do
    expect { described_class.new({}, []) }
      .to raise_error(Thor::Error, /No sources specified/)
  end

  describe 'writing records to disk' do
    let(:output_dir) { Dir.mktmpdir('ammitto-fetch') }

    after { FileUtils.remove_entry(output_dir) }

    def entity(name:, reference_number:)
      Ammitto::Sources::Tr::SanctionedEntity.new(
        name: name, reference_number: reference_number
      )
    end

    def save(entities)
      list = Ammitto::Sources::Tr::SanctionsList.new(entities: entities)
      described_class.new({}, ['tr'])
                     .send(:save_as_yaml, :tr, list, output_dir)
    end

    def records_on_disk
      Dir.children(output_dir).reject { |f| f == '_index.yaml' }
    end

    it 'gives every record its own file' do
      count = save([entity(name: 'A', reference_number: '1'),
                    entity(name: 'B', reference_number: '2')])

      expect(records_on_disk).to contain_exactly('tr-1.yaml', 'tr-2.yaml')
      expect(count).to eq(2)
    end

    it 'fails the source rather than overwriting one record with another' do
      # File.write truncates, so this used to leave one designee on disk
      # and no trace of the other behind a successful run.
      expect do
        save([entity(name: 'FIRST', reference_number: '5'),
              entity(name: 'SECOND', reference_number: '5')])
      end.to raise_error(RuntimeError, /filename collision/)
    end

    it 'names the discarded record so it can be found' do
      expect do
        save([entity(name: 'FIRST', reference_number: '5'),
              entity(name: 'SECOND', reference_number: '5')])
      end.to raise_error(RuntimeError, /tr-5\.yaml.*"SECOND"/)
    end

    it 'writes nothing at all when a collision is detected' do
      # A refused harvest must leave the previous corpus untouched rather
      # than half-replaced, so the collision is resolved before any write.
      expect do
        save([entity(name: 'OK', reference_number: '1'),
              entity(name: 'FIRST', reference_number: '5'),
              entity(name: 'SECOND', reference_number: '5')])
      end.to raise_error(RuntimeError)

      expect(Dir.children(output_dir)).to be_empty
    end

    it 'leaves an existing corpus byte-for-byte intact when it refuses' do
      # The record the failing run would have rewritten, and the index
      # describing the last good harvest, must both survive untouched.
      File.write(File.join(output_dir, 'tr-1.yaml'), "previous harvest\n")
      File.write(File.join(output_dir, '_index.yaml'), "count: 1\n")
      before = Dir.children(output_dir).to_h do |name|
        [name, File.read(File.join(output_dir, name))]
      end

      expect do
        save([entity(name: 'REWRITTEN', reference_number: '1'),
              entity(name: 'FIRST', reference_number: '5'),
              entity(name: 'SECOND', reference_number: '5')])
      end.to raise_error(RuntimeError)

      after = Dir.children(output_dir).to_h do |name|
        [name, File.read(File.join(output_dir, name))]
      end
      expect(after).to eq(before)
    end

    it 'names every discarded record when three claim one filename' do
      expect do
        save([entity(name: 'FIRST', reference_number: '5'),
              entity(name: 'SECOND', reference_number: '5'),
              entity(name: 'THIRD', reference_number: '5')])
      end.to raise_error(RuntimeError, /discard 2 record\(s\).*"SECOND", "THIRD"/)
    end

    it 'collapses a byte-identical repeated row without failing' do
      # An upstream sheet that lists one row twice loses nothing by
      # writing it once; only differing content is data loss.
      count = save([entity(name: 'A', reference_number: '1'),
                    entity(name: 'A', reference_number: '1')])

      expect(records_on_disk).to contain_exactly('tr-1.yaml')
      expect(count).to eq(1)
    end

    it 'reports the number of files written, not the number of rows seen' do
      save([entity(name: 'A', reference_number: '1'),
            entity(name: 'A', reference_number: '1')])
      index = YAML.safe_load_file(File.join(output_dir, '_index.yaml'))

      expect(index['count']).to eq(records_on_disk.size)
    end

    it 'keeps two designees sharing a reserved reference apart' do
      dtsrc = 'DEFENSE TECHNOLOGY AND SCIENCE RESEARCH ÇENTER (DTSRC)'
      dio = 'DEFENCE INDUSTRIES ORGANISATION (DIO)'

      count = save([entity(name: dio, reference_number: '187'),
                    entity(name: dtsrc, reference_number: '187')])

      expect(count).to eq(2)
      expect(records_on_disk).to include('tr-187.yaml')
      expect(records_on_disk.size).to eq(2)
    end
  end
end
