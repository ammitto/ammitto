# frozen_string_literal: true

require 'tmpdir'
require 'yaml'
require 'thor'
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
RSpec.describe Ammitto::Cmd::FetchCommand do
  include HarvestFixtures

  describe 'a harvest far smaller than the last' do
    it 'refuses rather than publishing the remainder as the whole list' do
      command = described_class.new(thor_options, ['uk'])

      Dir.mktmpdir do |dir|
        previous_harvest(dir, 6334)

        error = refused_harvest(command, uk_records(200), dir)

        expect(error.class).to eq(Ammitto::ParseError)
        expect(error.message).to match(/produced 200 record\(s\) where the last one produced 6334/)
      end
    end

    it 'writes nothing at all, so a later run has yesterday intact' do
      command = described_class.new(thor_options, ['uk'])

      Dir.mktmpdir do |dir|
        previous_harvest(dir, 6334)
        refused_harvest(command, uk_records(200), dir)

        expect(written_records(dir)).to be_empty
      end
    end

    it 'accepts the drop when the operator says it is real' do
      command = described_class.new(thor_options(allow_shrink: true), ['uk'])

      Dir.mktmpdir do |dir|
        previous_harvest(dir, 6334)
        write_harvest(command, uk_records(200), dir)

        expect(written_records(dir).length).to eq(200)
      end
    end
  end

  describe 'the boundary' do
    it 'accepts exactly half, which is already an implausible day' do
      command = described_class.new(thor_options, ['uk'])

      Dir.mktmpdir do |dir|
        previous_harvest(dir, 400)
        write_harvest(command, uk_records(200), dir)

        expect(written_records(dir).length).to eq(200)
      end
    end

    it 'refuses one record below half' do
      command = described_class.new(thor_options, ['uk'])

      Dir.mktmpdir do |dir|
        previous_harvest(dir, 400)

        expect { write_harvest(command, uk_records(199), dir) }
          .to raise_error(Ammitto::ParseError)
      end
    end
  end

  describe 'when there is nothing to compare against' do
    it 'accepts a first harvest into an empty directory' do
      command = described_class.new(thor_options, ['uk'])

      Dir.mktmpdir do |dir|
        write_harvest(command, uk_records(3), dir)

        expect(written_records(dir).length).to eq(3)
      end
    end

    it 'accepts a previous harvest that recorded none' do
      # `#74` refuses a run that writes nothing, so a recorded zero comes
      # from elsewhere — a hand-placed index, an older gem. Comparing
      # against it is harmless: everything clears zero.
      command = described_class.new(thor_options, ['uk'])

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
      command = described_class.new(thor_options, ['uk'])

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
      command = described_class.new(thor_options, ['uk'])

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
      command = described_class.new(thor_options, ['uk'])

      Dir.mktmpdir do |dir|
        File.write(File.join(dir, '_index.yaml'),
                   { 'source' => 'uk', 'count' => 'lots' }.to_yaml)

        expect { write_harvest(command, uk_records(3), dir) }
          .to raise_error(Ammitto::ParseError, /no record count could be read/)
      end
    end

    it 'harvests anyway when the operator asks for it' do
      command = described_class.new(thor_options(allow_shrink: true), ['uk'])

      Dir.mktmpdir do |dir|
        File.write(File.join(dir, '_index.yaml'), "\tnot: [valid\n")
        write_harvest(command, uk_records(3), dir)

        expect(written_records(dir).length).to eq(3)
      end
    end
  end
end
