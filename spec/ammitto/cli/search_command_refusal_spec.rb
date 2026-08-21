# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'ammitto'
require 'ammitto/cli'
require 'ammitto/cli/search_command'
require 'ammitto/cli/data_command'
require 'ammitto/cli/export_command'
require 'ammitto/serialization/rdf_serializer'

# `ammitto search` must not answer a question it could not ask.
#
# When no data repository is available the command printed "Data repository not
# found", returned no results, and exited 0 — so the run looked like a
# successful search with no matches. A caller screening a name against a
# machine that had never cloned the data received a clean negative for every
# query, and a `--format json` caller received `[]` on stdout with a success
# status.
#
# `get` already refused this way, exiting 1. Search disagreeing with its own
# sibling was the defect.
RSpec.describe Ammitto::Cmd::SearchCommand do
  let(:empty_dir) { Dir.mktmpdir('ammitto-no-data') }

  after { FileUtils.remove_entry(empty_dir) if File.directory?(empty_dir) }

  def run_search(format: nil)
    opts = { data_repository: empty_dir }
    opts[:format] = format if format
    described_class.new(opts, 'mohammad').run
  end

  it 'exits nonzero rather than reporting no results' do
    expect { run_search }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
  end

  it 'exits nonzero on the json path too' do
    expect { run_search(format: 'json') }
      .to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
  end

  it 'writes nothing to stdout, so a json caller cannot parse an empty answer' do
    expect do
      run_search(format: 'json')
    rescue SystemExit
      # the refusal under test
    end.not_to output.to_stdout
  end

  describe 'the sibling commands that had the same defect' do
    # `ammitto data pull/query/get/sources/stats` each printed "Repository
    # not cloned" and returned, so the process exited 0. query and get are
    # the dangerous pair: an empty answer from a machine that never had the
    # data reads as a clean screening result.
    %i[run_pull run_query run_get run_sources run_stats].each do |command|
      it "#{command} exits nonzero rather than returning quietly" do
        cmd = Ammitto::Cmd::DataCommand.new({ path: empty_dir }, 'status')
        repo = instance_double(Ammitto::Data::Repository, cloned?: false)
        allow(cmd).to receive(:repo).and_return(repo)

        expect { cmd.send(command) }
          .to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      end
    end
  end

  # The refusal is only useful if it reaches stderr: stdout is the machine
  # channel, and a message written there is read as output.
  it 'writes the refusal to stderr, not stdout' do
    expect do
      expect { described_class.new({}, 'anything').run }.to raise_error(SystemExit)
    end.to output(/Data repository not found/).to_stderr
  end

  describe 'get, which had the same message on the wrong channel' do
    it 'writes its refusal to stderr too' do
      require 'ammitto/cli/get_command'
      cmd = Ammitto::Cmd::GetCommand.new({ 'data_repository' => '/nonexistent' }, 'x')
      expect do
        expect { cmd.run }.to raise_error(SystemExit)
      end.to output(/Data repository not found/).to_stderr
    end
  end

  describe 'status, which reported an unreadable cache as zero entities' do
    it 'reports error rather than a clean count' do
      require 'ammitto/cli/status_command'
      Dir.mktmpdir do |dir|
        # source_status joins cache_dir with 'cache/sources', so the stub
        # must be the directory ABOVE the cache, not the cache itself.
        FileUtils.mkdir_p(File.join(dir, 'cache', 'sources'))
        File.write(File.join(dir, 'cache', 'sources', 'eu.jsonld'), 'not json{')
        cmd = Ammitto::Cmd::StatusCommand.new({})
        allow(cmd).to receive(:cache_dir).and_return(dir)

        st = cmd.send(:source_status, :eu)

        expect(st[:status]).to eq('error')
        expect(st[:entities]).to eq(0)
      end
    end
  end

  # export wrote an empty .ttl, printed "Exported" and exited 0 when the
  # cache could not be parsed — a file asserting this source sanctions
  # nobody, produced because we could not read it.
  describe 'export, the fourth place this defect was hiding' do
    it 'refuses rather than exporting an empty graph' do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, 'cache', 'sources'))
        File.write(File.join(dir, 'cache', 'sources', 'eu.jsonld'), 'not json{')
        cmd = Ammitto::Cmd::ExportCommand.new({ 'output_dir' => dir }, 'ttl')
        allow(cmd).to receive_messages(cache_dir: dir, parse_sources: [:eu])

        expect do
          expect { cmd.run }
            .to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
        end.to output(/eu\.jsonld could not be read/).to_stderr
      end
    end

    # The first version of this rescue caught three error classes by name
    # and missed these. A cache is unreadable for more reasons than a
    # parse error, and each has to say WHICH cache.
    {
      'malformed JSON' => 'not json{',
      'a non-UTF-8 byte sequence' => "\xff\xfe{\"@graph\":[]}"
    }.each do |description, content|
      it "names the cache when it holds #{description}" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'eu.jsonld')
          File.binwrite(path, content)
          cmd = Ammitto::Cmd::ExportCommand.new({}, 'ttl')

          expect { cmd.send(:load_entities_from_cache, path) }
            .to raise_error(Ammitto::CacheError, /eu\.jsonld/)
        end
      end
    end

    # File.read tags the string with Encoding.default_external, so under a
    # US-ASCII locale a valid UTF-8 cache holding an accented name was
    # judged invalid and refused. Refusing good data is the same lie as
    # accepting bad data, pointed the other way.
    it 'reads a valid UTF-8 cache whatever the external encoding is' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'eu.jsonld')
        File.write(path, JSON.generate(
                           '@graph' => [{ '@id' => 'a', '@type' => 'PersonEntity',
                                          'name' => 'Renée' }]
                         ))
        cmd = Ammitto::Cmd::ExportCommand.new({}, 'ttl')

        original = Encoding.default_external
        begin
          Encoding.default_external = Encoding::US_ASCII
          expect(cmd.send(:load_entities_from_cache, path).length).to eq(1)
        ensure
          Encoding.default_external = original
        end
      end
    end

    it 'lets a genuine export bug through rather than blaming the cache' do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, 'cache', 'sources'))
        File.write(File.join(dir, 'cache', 'sources', 'eu.jsonld'),
                   JSON.generate('@graph' => []))
        cmd = Ammitto::Cmd::ExportCommand.new({ 'output_dir' => dir }, 'ttl')
        allow(cmd).to receive_messages(cache_dir: dir, parse_sources: [:eu])
        allow(Ammitto::Serialization::RdfSerializer)
          .to receive(:new).and_raise(ArgumentError, 'serializer bug')

        expect { cmd.run }.to raise_error(ArgumentError, 'serializer bug')
      end
    end
  end
end
