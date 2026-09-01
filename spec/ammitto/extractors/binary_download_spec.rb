# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'tempfile'
# Explicitly, because the extractors require it inside #fetch. Without it,
# `verify_partial_doubles` has no URI.open to verify the stub against and
# this file passes only when some earlier spec happened to load it.
require 'open-uri'
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

      before do
        allow(Tempfile).to receive(:new).and_return(temp_file)
        allow(temp_file).to receive(:binmode).and_call_original
        allow(URI).to receive(:open) do |*, &block|
          block ? block.call(StringIO.new("PK\x03\x04payload\nwith\nnewlines")) : StringIO.new('x')
        end
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
        allow(URI).to receive(:open).and_raise(SocketError, 'host unreachable')
        path = temp_file.path

        expect { extractor.fetch }.to raise_error(SocketError)
        expect(File.exist?(path)).to be(false)
      end

      # Disposal must not become the reported failure.
      it 'still reports the download error when disposal fails' do
        allow(URI).to receive(:open).and_raise(SocketError, 'host unreachable')
        allow(temp_file).to receive(:unlink).and_raise(Errno::EACCES)

        expect { extractor.fetch }.to raise_error(SocketError, /host unreachable/)
      end

      # These sources 403 the default Ruby agent, so the header is part of
      # the request contract. Asserted as a POSITIONAL hash with string keys,
      # which is how every other call site in BaseExtractor passes open-uri
      # options; a keyword splat reaches open_uri identically today but
      # relies on URI.open's keyrest forwarding, which is subtler than it
      # needs to be.
      it 'sends the user agent as a positional options hash' do
        extractor.fetch

        expect(URI).to have_received(:open).with(
          an_instance_of(String), { 'User-Agent' => 'Mozilla/5.0' }
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
