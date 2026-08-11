# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/extractors/nz_extractor'

RSpec.describe Ammitto::Extractors::NzExtractor do
  # The helper's own examples prove which hops it follows. They prove
  # nothing about this extractor's temp-file lifecycle, which is where
  # the real risk lives: a download that fails after the Tempfile is
  # created must not strand it, because FetchCommand's ensure block
  # only disposes of files that reached the parser.
  subject(:extractor) { described_class.new }

  let(:client) { Ammitto::Extractors::HttpClient }

  describe '#fetch' do
    it 'writes the downloaded bytes and returns a readable path' do
      allow(client).to receive(:get).and_return("PK\x03\x04binary")

      path = extractor.fetch

      expect(File.binread(path)).to eq("PK\x03\x04binary")
    ensure
      extractor.cleanup
    end

    it 'sends the user agent MFAT requires' do
      allow(client).to receive(:get).and_return('x')

      extractor.fetch

      expect(client).to have_received(:get).with(
        described_class::RUSSIA_SANCTIONS_URL,
        headers: { 'User-Agent' => described_class::USER_AGENT }
      )
    ensure
      extractor.cleanup
    end

    it 'closes the file it hands to the parser' do
      allow(client).to receive(:get).and_return('x')

      extractor.fetch

      expect(extractor.instance_variable_get(:@temp_file)).to be_closed
    ensure
      extractor.cleanup
    end

    context 'when the download fails' do
      before { allow(client).to receive(:get).and_raise(OpenURI::HTTPError.new('403', nil)) }

      it 're-raises the original error rather than a cleanup error' do
        expect { extractor.fetch }.to raise_error(OpenURI::HTTPError, /403/)
      end

      # The download error is what the operator has to act on. A
      # platform that refuses to unlink an open file, or any other
      # disposal failure, must not overwrite it with a less useful
      # error about a temp file.
      it 'still reports the download error when cleanup itself fails' do
        allow(Tempfile).to receive(:new).and_wrap_original do |orig, *args|
          orig.call(*args).tap do |f|
            allow(f).to receive(:unlink).and_raise(Errno::EACCES)
          end
        end

        expect { extractor.fetch }.to raise_error(OpenURI::HTTPError, /403/)
      end

      it 'leaves no temp file on disk' do
        paths = []
        allow(Tempfile).to receive(:new).and_wrap_original do |orig, *args|
          orig.call(*args).tap { |f| paths << f.path }
        end

        expect { extractor.fetch }.to raise_error(OpenURI::HTTPError)

        expect(paths).not_to be_empty
        expect(paths.select { |p| File.exist?(p) }).to be_empty
      end

      it 'closes the descriptor, not just the pathname' do
        files = []
        allow(Tempfile).to receive(:new).and_wrap_original do |orig, *args|
          orig.call(*args).tap { |f| files << f }
        end

        expect { extractor.fetch }.to raise_error(OpenURI::HTTPError)

        # unlink alone removes the name and leaves the handle open until
        # GC — the defect this example exists to catch.
        expect(files.first).to be_closed
      end
    end
  end

  describe '#cleanup' do
    it 'is safe to call twice' do
      allow(client).to receive(:get).and_return('x')
      extractor.fetch

      expect { 2.times { extractor.cleanup } }.not_to raise_error
    end

    it 'is safe to call when nothing was ever fetched' do
      expect { extractor.cleanup }.not_to raise_error
    end
  end
end
