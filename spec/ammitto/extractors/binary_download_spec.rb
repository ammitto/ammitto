# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'tempfile'
require 'ammitto/extractors/au_extractor'
require 'ammitto/extractors/tr_extractor'
require 'ammitto/extractors/eu_vessels_extractor'

# The three XLSX downloaders covered here, in one place, because the
# defect is a property of the class rather than of any one source. NZ also
# downloads an XLSX; it already opens binary and is not changed here.
#
# A Tempfile opened in text mode expands each 0x0A to 0x0D 0x0A on Windows.
# An XLSX is a ZIP container, so the bytes written are not the bytes the
# source published and the archive cannot be relied on as a workbook.
#
# Linux and macOS do not translate, so that corruption cannot be reproduced
# here. `have_received(:binmode)` is the portable observable; the byte
# assertion is what fails on a translating platform. `ci.yml` is
# Ubuntu-only, and `rake.yml` delegates to an external Metanorma workflow
# whose matrix is not in this repository.
#
# Scope: these three only. UsExtractor writes its ZIP through a text-mode
# Tempfile too and is not touched here. NzExtractor and UnVesselsExtractor
# already call binmode, but their specs do not assert it and their payloads
# carry no 0x0A, so that call is correct and unguarded.
RSpec.describe 'binary downloads' do
  %w[
    Ammitto::Extractors::AuExtractor
    Ammitto::Extractors::TrExtractor
    Ammitto::Extractors::EuVesselsExtractor
  ].each do |class_name|
    describe class_name do
      subject(:extractor) { Object.const_get(class_name).new }

      let(:temp_file) { Tempfile.new(%w[binary_spec .xlsx]) }
      let(:client) { Ammitto::Extractors::HttpClient }

      before do
        allow(Tempfile).to receive(:new).and_return(temp_file)
        allow(temp_file).to receive(:binmode).and_call_original
        allow(client).to receive(:get).and_return("PK\x03\x04payload\nwith\nnewlines")
      end

      after do
        temp_file.close unless temp_file.closed?
        temp_file.unlink if File.exist?(temp_file.path.to_s)
      rescue StandardError
        nil
      end

      # The leak Copilot found: a download that raises after Tempfile.new
      # left the file on disk, because FetchCommand's ensure block only
      # disposes of what reached the parser.
      it 'disposes of the temp file when the download fails' do
        allow(client).to receive(:get).and_raise(SocketError, 'host unreachable')
        path = temp_file.path

        expect { extractor.fetch }.to raise_error(SocketError)
        expect(File.exist?(path)).to be(false)
      end

      # Disposal must not become the reported failure.
      it 'still reports the download error when disposal fails' do
        allow(client).to receive(:get).and_raise(SocketError, 'host unreachable')
        allow(temp_file).to receive(:unlink).and_raise(Errno::EACCES)

        expect { extractor.fetch }.to raise_error(SocketError, /host unreachable/)
      end

      # These sources 403 the default Ruby agent, so the header is part of
      # the request contract.
      it 'sends the user agent as a headers keyword' do
        extractor.fetch

        expect(client).to have_received(:get).with(
          an_instance_of(String), headers: { 'User-Agent' => 'Mozilla/5.0' }
        )
      end

      it 'opens the download in binary mode' do
        extractor.fetch

        expect(temp_file).to have_received(:binmode)
      end

      it 'writes the bytes it was given, unaltered' do
        extractor.fetch

        expect(File.binread(temp_file.path))
          .to eq("PK\x03\x04payload\nwith\nnewlines")
      end
    end
  end
end
