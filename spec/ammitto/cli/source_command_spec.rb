# frozen_string_literal: true

require 'tmpdir'
require 'yaml'
require 'ammitto'
require 'ammitto/cli'
require 'ammitto/cli/source_command'
require 'ammitto/data/japan/meti/extractor'

# `ammitto source japan fetch meti` — the invocation the CLI's own help text
# gives — never reached the extractor it names.
#
# Three separate faults stacked. `CLI#source` handed Thor `[country] + args`,
# but Thor dispatches on the first element, so it looked for a command called
# `japan`; `SourceCommand` defined no `exit_on_failure?`, so that miss printed
# `Could not find command "japan"` and exited 0; and the Japan arm named
# `METI`, a constant that does not exist, then called `fetch_to_yaml`, a method
# the extractor does not define. `JpExtractor#fetch` sends operators here —
# "for programmatic access use Ammitto::Data::Japan::Meti::Extractor" — so the
# one documented route to Japan's data pointed at a NameError.
RSpec.describe Ammitto::Cmd::SourceCommand do
  include MetiExtractorFixtures

  describe '.exit_on_failure?' do
    it 'is true, so a failed command cannot report success' do
      expect(described_class.exit_on_failure?).to be true
    end
  end

  describe 'argument order' do
    it 'puts the subcommand first, where Thor dispatches from' do
      allow(described_class).to receive(:start)

      Ammitto::CLI.new.source('japan', 'fetch', 'meti')

      expect(described_class).to have_received(:start)
        .with(%w[fetch japan meti])
    end

    it 'repairs China by the same route, which was equally unreachable' do
      allow(described_class).to receive(:start)

      Ammitto::CLI.new.source('china', 'fetch', 'mfa-anti-sanction-list')

      expect(described_class).to have_received(:start)
        .with(%w[fetch china mfa-anti-sanction-list])
    end
  end

  describe 'fetch japan meti' do
    it 'writes the parsed list and reports its size' do
      stub_meti_extractor(meti_list(3))

      Dir.mktmpdir do |dir|
        expect { described_class.start(['fetch', 'japan', 'meti', '--output-dir', dir]) }
          .to output(/Fetched 3 entities to /).to_stdout

        written = YAML.safe_load_file(File.join(dir, 'foreign-user-list.yaml'))
        expect(written['entities'].length).to eq(3)
      end
    end

    it 'is reachable through the top-level CLI, argv and all' do
      stub_meti_extractor(meti_list(2))

      Dir.mktmpdir do |dir|
        expect { Ammitto::CLI.start(['source', 'japan', 'fetch', 'meti', '--output-dir', dir]) }
          .to output(/Fetched 2 entities to /).to_stdout

        expect(File.exist?(File.join(dir, 'foreign-user-list.yaml'))).to be true
      end
    end

    it 'downloads into the output directory by default' do
      download_dir = capture_meti_download_dir

      Dir.mktmpdir do |dir|
        expect { described_class.start(['fetch', 'japan', 'meti', '--output-dir', dir]) }
          .to output(/Fetched 1 entity to /).to_stdout

        expect(download_dir.value).to eq(dir)
        expect(Dir.exist?(download_dir.value)).to be true
      end
    end

    # The assertion that matters is the last one. An earlier version of
    # this passed the extractor `output_dir: nil` and checked only that
    # nil arrived, which proved delegation and not deletion — the file
    # still landed in the shared `Dir.tmpdir` and stayed there.
    it 'deletes the download directory under --no-save-xlsx' do
      download_dir = capture_meti_download_dir

      Dir.mktmpdir do |dir|
        expect do
          described_class.start(
            ['fetch', 'japan', 'meti', '--output-dir', dir, '--no-save-xlsx']
          )
        end.to output(/Fetched 1 entity to /).to_stdout

        expect(download_dir.value).not_to eq(dir)
        expect(Dir.exist?(download_dir.value)).to be false
      end
    end

    it 'refuses a list that parsed to zero entities' do
      stub_meti_extractor(meti_list(0))

      Dir.mktmpdir do |dir|
        error = begin
          described_class.start(['fetch', 'japan', 'meti', '--output-dir', dir])
          nil
        rescue Ammitto::Error => e
          e
        end

        expect(error.class).to eq(Ammitto::ParseError)
        expect(error.message).to match(/parsed to zero entities/)
        expect(File.exist?(File.join(dir, 'foreign-user-list.yaml'))).to be false
      end
    end
  end
end
