# frozen_string_literal: true

require 'tmpdir'
require 'yaml'
require 'thor'
require 'fileutils'
require 'ammitto'
require 'ammitto/cli'
require 'ammitto/cli/fetch_command'

# A harvest that produced far less than the last one is a broken parser
# until proven otherwise.
#
# `#74` refuses a run that wrote nothing, and `#77` refuses a record with
# no usable identifier. Between them sits the case neither can see: enough
# of the document still parses to produce real, distinctly-named records,
# but most of it no longer matches. Every gate passes — the count is not
# zero, the records are not blank — and the run publishes a fraction of a
# sanctions list as though it were the list.
#
# Nothing compared a harvest to the one before it. `_index.yaml` has
# recorded the previous count all along.
RSpec.describe Ammitto::Cmd::Fetch::CollisionAndCollapseGuard do
  include HarvestFixtures

  describe 'a harvest far smaller than the last' do
    it 'refuses rather than publishing the remainder as the whole list' do
      command = Ammitto::Cmd::FetchCommand.new(thor_options, ['uk'])

      Dir.mktmpdir do |dir|
        previous_harvest(dir, 6334)

        error = refused_harvest(command, uk_records(200), dir)

        expect(error.class).to eq(Ammitto::ParseError)
        expect(error.message).to match(/produced 200 record\(s\) where the last one produced 6334/)
      end
    end

    it 'writes nothing at all, so a later run has yesterday intact' do
      command = Ammitto::Cmd::FetchCommand.new(thor_options, ['uk'])

      Dir.mktmpdir do |dir|
        previous_harvest(dir, 6334)
        refused_harvest(command, uk_records(200), dir)

        expect(written_records(dir)).to be_empty
      end
    end

    it 'accepts the drop when the operator says it is real' do
      command = Ammitto::Cmd::FetchCommand.new(thor_options(allow_shrink: true), ['uk'])

      Dir.mktmpdir do |dir|
        previous_harvest(dir, 6334)
        write_harvest(command, uk_records(200), dir)

        expect(written_records(dir).length).to eq(200)
      end
    end
  end

  describe 'the boundary' do
    it 'accepts exactly half, which is already an implausible day' do
      command = Ammitto::Cmd::FetchCommand.new(thor_options, ['uk'])

      Dir.mktmpdir do |dir|
        previous_harvest(dir, 400)
        write_harvest(command, uk_records(200), dir)

        expect(written_records(dir).length).to eq(200)
      end
    end

    it 'refuses one record below half' do
      command = Ammitto::Cmd::FetchCommand.new(thor_options, ['uk'])

      Dir.mktmpdir do |dir|
        previous_harvest(dir, 400)

        expect { write_harvest(command, uk_records(199), dir) }
          .to raise_error(Ammitto::ParseError)
      end
    end
  end

  describe 'when there is nothing to compare against' do
    it 'accepts a first harvest into an empty directory' do
      command = Ammitto::Cmd::FetchCommand.new(thor_options, ['uk'])

      Dir.mktmpdir do |dir|
        write_harvest(command, uk_records(3), dir)

        expect(written_records(dir).length).to eq(3)
      end
    end

    it 'accepts a previous harvest that recorded none' do
      # `#74` refuses a run that writes nothing, so a recorded zero comes
      # from elsewhere — a hand-placed index, an older gem. Comparing
      # against it is harmless: everything clears zero.
      command = Ammitto::Cmd::FetchCommand.new(thor_options, ['uk'])

      Dir.mktmpdir do |dir|
        previous_harvest(dir, 0)
        write_harvest(command, uk_records(3), dir)

        expect(written_records(dir).length).to eq(3)
      end
    end
  end

  describe 'an index that exists and cannot be read' do
    # Absence means first harvest. A present file that yields no count is
    # different: skipping the comparison there would let a corrupt index
    # switch this gate off without saying so, which is the shape of
    # failure the gate exists to catch.
    it 'refuses rather than harvesting without the comparison' do
      command = Ammitto::Cmd::FetchCommand.new(thor_options, ['uk'])

      Dir.mktmpdir do |dir|
        File.write(File.join(dir, '_index.yaml'), "\tnot: [valid\n")

        error = refused_harvest(command, uk_records(3), dir)

        expect(error.class).to eq(Ammitto::ParseError)
        expect(error.message).to match(/no record count could be read/)
        expect(written_records(dir)).to be_empty
      end
    end

    it 'refuses an index that parsed but is not a mapping' do
      # A bare list, a number or `false` parses cleanly and has no key to
      # read. Left unchecked it escaped as a TypeError rather than a
      # refusal, which is a crash where a decision belongs.
      command = Ammitto::Cmd::FetchCommand.new(thor_options, ['uk'])

      ['[]', '3', 'false'].each do |document|
        Dir.mktmpdir do |dir|
          File.write(File.join(dir, '_index.yaml'), "---\n#{document}\n")

          expect { write_harvest(command, uk_records(3), dir) }
            .to raise_error(Ammitto::ParseError, /no record count could be read/)
          expect(written_records(dir)).to be_empty
        end
      end
    end

    it 'refuses an index whose count is not a number' do
      command = Ammitto::Cmd::FetchCommand.new(thor_options, ['uk'])

      Dir.mktmpdir do |dir|
        File.write(File.join(dir, '_index.yaml'),
                   { 'source' => 'uk', 'count' => 'lots' }.to_yaml)

        expect { write_harvest(command, uk_records(3), dir) }
          .to raise_error(Ammitto::ParseError, /no record count could be read/)
      end
    end

    it 'harvests anyway when the operator asks for it' do
      command = Ammitto::Cmd::FetchCommand.new(thor_options(allow_shrink: true), ['uk'])

      Dir.mktmpdir do |dir|
        File.write(File.join(dir, '_index.yaml'), "\tnot: [valid\n")
        write_harvest(command, uk_records(3), dir)

        expect(written_records(dir).length).to eq(3)
      end
    end
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
      Ammitto::Cmd::FetchCommand.new({}, ['tr'])
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
      end.to raise_error(Ammitto::Cmd::Fetch::FilenameCollisionError, /filename collision/)
    end

    it 'names the discarded record so it can be found' do
      expect do
        save([entity(name: 'FIRST', reference_number: '5'),
              entity(name: 'SECOND', reference_number: '5')])
      end.to raise_error(Ammitto::Cmd::Fetch::FilenameCollisionError, /tr-5\.yaml.*"SECOND"/)
    end

    it 'writes nothing at all when a collision is detected' do
      # A refused harvest must leave the previous corpus untouched rather
      # than half-replaced, so the collision is resolved before any write.
      expect do
        save([entity(name: 'OK', reference_number: '1'),
              entity(name: 'FIRST', reference_number: '5'),
              entity(name: 'SECOND', reference_number: '5')])
      end.to raise_error(Ammitto::Cmd::Fetch::FilenameCollisionError)

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
      end.to raise_error(Ammitto::Cmd::Fetch::FilenameCollisionError)

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
      end.to raise_error(Ammitto::Cmd::Fetch::FilenameCollisionError, /discard 2 record\(s\).*"SECOND", "THIRD"/)
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
