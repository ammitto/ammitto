# frozen_string_literal: true

require 'tmpdir'
require 'thor'
require 'ammitto'
require 'ammitto/cli'
require 'ammitto/cli/fetch_command'

RSpec.describe Ammitto::Cmd::Fetch::SourceRegistry do
  # `fetch_source`, `dry_run`, `sources` and `initialize` below are
  # FetchCommand's own methods, not SourceRegistry's; they are exercised
  # here through a FetchCommand instance because what is under test is
  # NO_FETCH_PATH data flowing into that behaviour, and NO_FETCH_PATH has
  # no meaning outside a caller that consumes it. `source_model_class_for`
  # and `extractor_class_for`, SourceRegistry's own methods, are exercised
  # directly below instead.
  include StdoutCaptureHelper

  it 'refuses CN rather than reporting a fetch it cannot perform' do
    # data-cn curates its YAML with its own tooling; this command has no
    # path to that data and used to say otherwise.
    cmd = Ammitto::Cmd::FetchCommand.new({}, ['cn'])
    result = cmd.send(:fetch_source, :cn)

    expect(result[:status]).to eq(:error)
    expect(result[:error]).to match(/no automated fetch path/)
  end

  it 'reports RU as blocked by the anti-bot wall instead of a silent zero-entity scrape' do
    # mid.ru serves a JavaScript anti-bot challenge to non-browser
    # clients; the scraper structurally yields zero entities, which used
    # to count as success. The command must refuse before scraping.
    Dir.mktmpdir('ammitto-fetch-ru') do |dir|
      cmd = Ammitto::Cmd::FetchCommand.new({ output_dir: dir }, ['ru'])
      result = cmd.send(:fetch_source, :ru)

      expect(result[:status]).to eq(:error)
      expect(result[:error]).to match(/blocked.*anti-bot challenge/)
      expect(Dir.children(dir)).to be_empty
    end
  end

  it 'refuses JP rather than saving zero files and calling it success' do
    # jp IS fetched and processed — by data-jp's own scripts, into the
    # curated sources/ that harmonize reads for its 5,097 entities. What
    # this command's jp path did was save nothing and exit 0.
    cmd = Ammitto::Cmd::FetchCommand.new({}, ['jp'])
    result = cmd.send(:fetch_source, :jp)

    expect(result[:status]).to eq(:error)
    expect(result[:error]).to match(/no automated fetch path/)
  end

  it 'does not advertise an endpoint for a source it will refuse to fetch' do
    # `fetch jp` refuses, but --dry-run resolved the extractor directly and
    # printed JpExtractor's URL, so the two disagreed on the one path a user
    # checks before running anything.
    cmd = Ammitto::Cmd::FetchCommand.new({ dry_run: true }, %w[jp cn ru])
    output = capture_stdout { cmd.send(:dry_run) }

    expect(output).to include('no automated fetch path')
    expect(output).not_to match(%r{jp:\s+https?://})
    expect(output).not_to match(%r{cn:\s+https?://})
    expect(output).not_to match(%r{ru:\s+https?://})
  end

  it 'requires sources or --all' do
    expect { Ammitto::Cmd::FetchCommand.new({}, []) }
      .to raise_error(Thor::Error, /No sources specified/)
  end

  it 'excludes cn, ru and jp from --all so full runs can succeed' do
    # None of the three can be fetched by this command. cn and jp are
    # produced by their own data repos' tooling, and mid.ru answers
    # non-browser clients with an anti-bot challenge. A full run must
    # skip them rather than fail on them.
    cmd = Ammitto::Cmd::FetchCommand.new({ all: true }, [])

    expect(cmd.sources).not_to include(:cn)
    expect(cmd.sources).not_to include(:ru)
    expect(cmd.sources).not_to include(:jp)
    expect(cmd.sources)
      .to match_array(Ammitto::Config::Defaults::ALL_SOURCES - %i[cn ru jp])
  end

  describe '#source_model_class_for' do
    subject(:registry) { Class.new { include Ammitto::Cmd::Fetch::SourceRegistry }.new }

    it 'resolves a real source to its Lutaml::Model class' do
      expect(registry.send(:source_model_class_for, :au))
        .to eq(Ammitto::Sources::Au::SanctionsList)
    end

    it 'returns nil for a source with no model class' do
      expect(registry.send(:source_model_class_for, :not_a_source)).to be_nil
    end
  end

  describe '#extractor_class_for' do
    subject(:registry) { Class.new { include Ammitto::Cmd::Fetch::SourceRegistry }.new }

    it 'resolves a real source to its extractor class' do
      expect(registry.send(:extractor_class_for, :au))
        .to eq(Ammitto::Extractors::AuExtractor)
    end

    it 'returns nil for a source with no registered extractor' do
      expect(registry.send(:extractor_class_for, :not_a_source)).to be_nil
    end
  end
end
