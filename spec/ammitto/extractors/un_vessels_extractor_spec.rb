# frozen_string_literal: true

require 'spec_helper'
require 'open-uri'
require 'stringio'
require 'tempfile'

# Require the extractor
require_relative '../../../lib/ammitto/extractors/un_vessels_extractor'

RSpec.describe Ammitto::Extractors::UnVesselsExtractor do
  let(:extractor) { described_class.new }

  # Capture the path of the Tempfile the extractor creates: after a
  # cleanup unlinks it, Tempfile#path returns nil, so the path must be
  # taken at creation time to assert the file is gone.
  def capture_tempfile_path
    path = nil
    allow(Tempfile).to receive(:new).and_wrap_original do |original, *args|
      original.call(*args).tap { |file| path = file.path }
    end
    -> { path }
  end

  describe '#fetch' do
    it 'disposes of the temp file when the download fails' do
      path = capture_tempfile_path
      allow(URI).to receive(:open).and_raise(SocketError, 'unreachable')

      expect { extractor.fetch }.to raise_error(SocketError)
      expect(File.exist?(path.call)).to be(false)
    end
  end

  describe '#run' do
    it 'disposes of the temp file on the legacy non-YAML path' do
      # The YAML pipeline disposes of the download in
      # FetchCommand#parse_pdf; the legacy run path never reaches it,
      # so run owns disposal there.
      path = capture_tempfile_path
      allow(URI).to receive(:open).and_yield(StringIO.new('%PDF-1.4'))

      result = extractor.run

      expect(result[:status]).to eq(:success)
      expect(File.exist?(path.call)).to be(false)
    end
  end
end
