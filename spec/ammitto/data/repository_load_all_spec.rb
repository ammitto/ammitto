# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'json'
require 'ammitto'

# `load_all` must not depend on a file that is not guaranteed to exist.
#
# The combined aggregate is written only under `harmonize --combine`, and the
# data repository's copy stopped advancing on 2026-07-22 — its harmonize
# workflow has failed every run since. Before this change, `load_all` raised
# NotFoundError in that case, so every unscoped `query` and `get` failed on a
# clone that holds the entire corpus under `sources/`.
RSpec.describe Ammitto::Data::Repository do
  include JsonLdFixtures

  subject(:repo) { described_class.new(local_path: dir) }

  let(:dir) { Dir.mktmpdir('ammitto-repo') }
  let(:api) { File.join(dir, 'api', 'v1') }
  let(:sources) { File.join(api, 'sources') }

  before { FileUtils.mkdir_p(sources) }
  after { FileUtils.remove_entry(dir) if File.directory?(dir) }

  context 'when the combined aggregate is present' do
    it 'reads it' do
      write_graph(File.join(api, 'all.jsonld'), %w[a b c])
      write_graph(File.join(sources, 'eu.jsonld'), %w[ignored])

      expect(repo.load_all.map { |n| n['@id'] }).to eq(%w[a b c])
    end

    it 'says nothing, because nothing is being substituted' do
      write_graph(File.join(api, 'all.jsonld'), %w[a b c])
      allow(Ammitto::Logger).to receive(:warn)

      repo.load_all

      expect(Ammitto::Logger).not_to have_received(:warn)
    end
  end

  context 'when the combined aggregate is absent' do
    it 'falls back to concatenating the per-source files' do
      write_graph(File.join(sources, 'eu.jsonld'), %w[eu-1 eu-2])
      write_graph(File.join(sources, 'us.jsonld'), %w[us-1])

      expect(repo.load_all.map { |n| n['@id'] }).to contain_exactly('eu-1', 'eu-2', 'us-1')
    end

    it 'reads the sources in a deterministic order' do
      # #get returns the first exact @id match and load_all does not
      # dedupe, so if two sources ever carry the same entity or entry id
      # the winner is whichever file is read first. That must not vary
      # between runs.
      write_graph(File.join(sources, 'us.jsonld'), %w[us-1])
      write_graph(File.join(sources, 'eu.jsonld'), %w[eu-1])

      expect(repo.load_all.map { |n| n['@id'] }).to eq(%w[eu-1 us-1])
    end

    it 'tolerates a source document with no @graph' do
      File.write(File.join(sources, 'empty.jsonld'), JSON.generate('@context' => 'x'))
      write_graph(File.join(sources, 'eu.jsonld'), %w[eu-1])

      expect(repo.load_all.map { |n| n['@id'] }).to eq(%w[eu-1])
    end

    it 'still raises when there is nothing to fall back to' do
      expect { repo.load_all }
        .to raise_error(Ammitto::NotFoundError, /no per-source files/)
    end

    # The warning is the whole point of the substitution being acceptable.
    # A caller handed a narrower dataset silently is back to the failure
    # this method exists to avoid, so the notice is behaviour, not noise.
    it 'says that it substituted, and how many files it read' do
      write_graph(File.join(sources, 'eu.jsonld'), %w[eu-1])
      write_graph(File.join(sources, 'us.jsonld'), %w[us-1])

      allow(Ammitto::Logger).to receive(:warn)

      repo.load_all

      expect(Ammitto::Logger)
        .to have_received(:warn).with(/reading 2 per-source files/)
    end

    it 'names the shared nodes as the thing the caller is not getting' do
      write_graph(File.join(sources, 'eu.jsonld'), %w[eu-1])

      allow(Ammitto::Logger).to receive(:warn)

      repo.load_all

      expect(Ammitto::Logger)
        .to have_received(:warn).with(/Shared nodes are not included/)
    end

    it 'says nothing when there is nothing to substitute with' do
      allow(Ammitto::Logger).to receive(:warn)

      expect { repo.load_all }.to raise_error(Ammitto::NotFoundError)
      expect(Ammitto::Logger).not_to have_received(:warn)
    end
  end
end
