# frozen_string_literal: true

require 'spec_helper'
require 'net/http'
require 'open-uri'
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

  # Real Net::HTTPResponse instances rather than doubles: the download
  # loop dispatches on is_a?(Net::HTTPSuccess) / is_a?(Net::HTTPRedirection),
  # which a verifying double does not satisfy.
  def http_response(klass, code, message, body: nil, location: nil)
    response = klass.new('1.1', code, message)
    allow(response).to receive(:body).and_return(body) if body
    response['Location'] = location if location
    response
  end

  describe '#fetch' do
    it 'disposes of the temp file when the download fails' do
      path = capture_tempfile_path
      allow(Net::HTTP).to receive(:start).and_raise(SocketError, 'unreachable')

      expect { extractor.fetch }.to raise_error(SocketError)
      expect(File.exist?(path.call)).to be(false)
    end

    it 'raises the open-uri error class on an HTTP failure' do
      # The 403-on-UA-change failure mode used to surface as
      # OpenURI::HTTPError; callers keep seeing that class now that
      # the download runs on Net::HTTP.
      path = capture_tempfile_path
      forbidden = http_response(Net::HTTPForbidden, '403', 'Forbidden')
      allow(Net::HTTP).to receive(:start).and_return(forbidden)

      expect { extractor.fetch }
        .to raise_error(OpenURI::HTTPError, '403 Forbidden')
      expect(File.exist?(path.call)).to be(false)
    end

    it 'follows a redirect to the relocated PDF' do
      moved = http_response(Net::HTTPFound, '302', 'Found',
                            location: 'https://main.un.org/moved.pdf')
      found = http_response(Net::HTTPOK, '200', 'OK', body: '%PDF-1.4')
      allow(Net::HTTP).to receive(:start).and_return(moved, found)

      pdf_path = extractor.fetch

      expect(File.binread(pdf_path)).to eq('%PDF-1.4')
      expect(Net::HTTP).to have_received(:start).twice
    ensure
      extractor.cleanup
    end

    it 'gives up after the redirect cap instead of looping' do
      path = capture_tempfile_path
      moved = http_response(Net::HTTPFound, '302', 'Found',
                            location: described_class::PDF_URL)
      allow(Net::HTTP).to receive(:start).and_return(moved)

      expect { extractor.fetch }.to raise_error(RuntimeError, /redirects/)
      expect(File.exist?(path.call)).to be(false)
    end
  end

  describe '#run' do
    it 'disposes of the temp file on the legacy non-YAML path' do
      # The YAML pipeline disposes of the download in
      # FetchCommand#parse_pdf; the legacy run path never reaches it,
      # so run owns disposal there.
      path = capture_tempfile_path
      success = http_response(Net::HTTPOK, '200', 'OK', body: '%PDF-1.4')
      allow(Net::HTTP).to receive(:start).and_return(success)

      result = extractor.run

      expect(result[:status]).to eq(:success)
      expect(File.exist?(path.call)).to be(false)
    end
  end
end
