# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'zip'
require 'ammitto/extractors/us_extractor'

RSpec.describe Ammitto::Extractors::UsExtractor do
  # OFAC publishes the same list twice: a legacy flat XML file and a newer
  # ZIP export. #fetch tries the legacy URL first and falls back to the ZIP.
  #
  # The fallback is the half with no coverage and the half that fails
  # unobserved. It runs inside a `rescue` clause, and a raise from inside a
  # rescue clause is not caught by a sibling rescue on the same body — so
  # every failure in it left the method as whatever raw exception the ZIP
  # code happened to produce, and the temp file it had already created
  # stayed on disk.
  subject(:extractor) { described_class.new }

  # A real archive, because the point is to exercise rubyzip rather than a
  # stub of it: this extractor is the only caller in the gem, so a stub
  # would prove nothing about whether the dependency resolves.
  # Asserted rather than waved through with any_args: treasury.gov serves
  # 403 to the default Ruby agent, so the header is part of the request
  # contract and a stub that ignores it would pass with the header dropped.
  let(:agent) { { 'User-Agent' => described_class::USER_AGENT } }

  def stub_zip_with(payload)
    allow(URI).to receive(:open)
      .with(described_class::SDN_ZIP_URL, agent) do |*, &block|
        block.call(StringIO.new(payload))
      end
  end

  def zip_bytes(entries)
    Zip::OutputStream.write_buffer do |zos|
      entries.each do |name, content|
        zos.put_next_entry(name)
        zos.write(content)
      end
    end.string
  end

  describe '#fetch' do
    context 'when the legacy URL answers' do
      it 'returns its body and never reaches the ZIP export' do
        allow(URI).to receive(:open)
          .with(described_class::LEGACY_SDN_URL, agent)
          .and_return(StringIO.new('<sdnList/>'))

        expect(extractor.fetch).to eq('<sdnList/>')
        expect(URI).not_to have_received(:open)
          .with(described_class::SDN_ZIP_URL, agent)
      end
    end

    context 'when the legacy URL fails and the ZIP export answers' do
      before do
        allow(URI).to receive(:open)
          .with(described_class::LEGACY_SDN_URL, agent)
          .and_raise(SocketError, 'legacy host unreachable')
      end

      # The working fallback, guarded so the refusal below cannot be
      # bought by breaking it.
      it 'returns the XML held inside the archive' do
        stub_zip_with(zip_bytes('sdn.xml' => '<sdnList><sdnEntry/></sdnList>'))

        expect(extractor.fetch).to eq('<sdnList><sdnEntry/></sdnList>')
      end

      # The interpolation evaluates #message BEFORE #report is entered, so
      # #report's own rescue never sees it. An exception whose message
      # formatter raises therefore escaped #fetch and took the fallback
      # with it -- the same class of loss as the closed stream below, one
      # layer earlier.
      it 'still falls back when the error cannot describe itself' do
        broken = Class.new(StandardError) do
          def message = raise(NoMethodError, 'message formatter broke')
        end
        allow(URI).to receive(:open)
          .with(described_class::LEGACY_SDN_URL, agent).and_raise(broken)
        stub_zip_with(zip_bytes('sdn.xml' => '<sdnList/>'))

        expect(extractor.fetch).to eq('<sdnList/>')
      end

      # `puts` raises IOError on a closed stream, and the progress line that
      # announces the fallback sits inside #fetch's rescue clause -- where a
      # raise is not caught by a sibling clause and escapes the method. An
      # unguarded line there does not just lose the logging, it loses the
      # fallback: measured on the unfixed code as IOError leaving #fetch
      # before the ZIP was ever requested.
      it 'still falls back when progress cannot be printed' do
        extractor.verbose = true
        stub_zip_with(zip_bytes('sdn.xml' => '<sdnList/>'))
        closed_stdout = StringIO.new
        closed_stdout.close
        original_stdout = $stdout
        $stdout = closed_stdout # rubocop:disable RSpec/ExpectOutput

        expect(extractor.fetch).to eq('<sdnList/>')
      ensure
        $stdout = original_stdout if original_stdout # rubocop:disable RSpec/ExpectOutput
      end

      # FetchCommand disposes only of what reaches parse_xlsx or parse_pdf.
      # us is an XML source, so it takes the branch that hands back a String
      # and never calls cleanup -- if the extractor does not dispose of the
      # archive itself, nothing does until the process exits.
      it 'disposes of the archive it downloaded' do
        temp_file = Tempfile.new(%w[us_sdn_spec .zip])
        path = temp_file.path
        allow(Tempfile).to receive(:new).and_return(temp_file)
        stub_zip_with(zip_bytes('sdn.xml' => '<sdnList/>'))

        extractor.fetch

        expect(File.exist?(path)).to be(false)
      end

      # Linux and macOS have no text-mode translation, so the corruption
      # this prevents cannot be reproduced here -- the call is the only
      # observable form the contract has off Windows. The effect itself is
      # verified by this gem's Windows CI.
      it 'opens the archive in binary mode' do
        temp_file = Tempfile.new(%w[us_sdn_spec .zip])
        allow(Tempfile).to receive(:new).and_return(temp_file)
        allow(temp_file).to receive(:binmode).and_call_original
        stub_zip_with(zip_bytes('sdn.xml' => '<sdnList/>'))

        extractor.fetch

        expect(temp_file).to have_received(:binmode)
      end

      # rubyzip closes the entry stream only in the block form
      # (rubyzip-2.4.1 lib/zip/entry.rb:577-584). Zip::InputStream exposes
      # no `closed?`, so the call shape is the only observable form this
      # contract has.
      it 'reads the entry through the closing block form' do
        stub_zip_with(zip_bytes('sdn.xml' => '<sdnList/>'))
        block_given_to_stream = nil
        allow_any_instance_of(Zip::Entry) # rubocop:disable RSpec/AnyInstance
          .to receive(:get_input_stream).and_wrap_original do |original, &block|
            block_given_to_stream = !block.nil?
            original.call(&block)
          end

        extractor.fetch

        expect(block_given_to_stream).to be(true)
      end

      # The archive handle is per-call state, and asserting only that a
      # second call returns is not enough -- unmodified main returns twice
      # too, leaking both archives. Each call must dispose of its OWN
      # tempfile, so both paths are named and both are checked.
      it 'disposes of each archive when called twice' do
        first = Tempfile.new(%w[us_sdn_spec_1 .zip])
        second = Tempfile.new(%w[us_sdn_spec_2 .zip])
        paths = [first.path, second.path]
        allow(Tempfile).to receive(:new).and_return(first, second)
        stub_zip_with(zip_bytes('sdn.xml' => '<sdnList/>'))

        2.times { expect(extractor.fetch).to eq('<sdnList/>') }

        expect(paths.map { |path| File.exist?(path) }).to eq([false, false])
        # `and_return(a, b)` repeats b forever, so a third Tempfile.new
        # would be handed the second one and go unnoticed. The count is
        # part of the assertion.
        expect(Tempfile).to have_received(:new).twice
      end
    end

    context 'when both downloads fail' do
      before do
        allow(URI).to receive(:open)
          .with(described_class::LEGACY_SDN_URL, agent)
          .and_raise(SocketError, 'legacy host unreachable')
        allow(URI).to receive(:open)
          .with(described_class::SDN_ZIP_URL, agent)
          .and_raise(SocketError, 'zip host unreachable')
      end

      # Naming both attempts is the point. An operator reading a red
      # harvest cannot act on a bare SocketError that does not say which
      # of the two OFAC endpoints produced it.
      it 'refuses with one typed error naming both attempts' do
        expect { extractor.fetch }.to raise_error(
          Ammitto::Error,
          /legacy host unreachable.*zip host unreachable/m
        )
      end

      # The counterpart of the ParseError example below. Two endpoints that
      # both failed to answer cannot be told apart, so this must NOT narrow
      # to ParseError -- `raise_error(Ammitto::Error)` alone would pass on
      # either, ParseError being a subclass.
      it 'does not report an unreachable endpoint as unusable content' do
        expect { extractor.fetch }.to(
          raise_error { |error| expect(error).to be_an_instance_of(Ammitto::Error) }
        )
      end

      # Disposal must not become the reported failure. NzExtractor#fetch
      # keeps the same contract, for the same reason: a cleanup that raises
      # on top of a download error would hide the cause the operator needs.
      it 'still reports the endpoint failure when disposal itself fails' do
        temp_file = Tempfile.new(%w[us_sdn_spec .zip])
        path = temp_file.path
        allow(Tempfile).to receive(:new).and_return(temp_file)
        allow(temp_file).to receive(:unlink).and_raise(
          Errno::EACCES, 'permission denied'
        )

        expect { extractor.fetch }.to raise_error(
          Ammitto::Error, /zip host unreachable/
        )
      ensure
        File.unlink(path) if path && File.exist?(path)
      end

      # $stderr can be closed or redirected by the embedding process, and
      # `warn` then raises from inside the very handler that exists to stop
      # a disposal failure replacing the cause.
      it 'survives a warning that cannot be written' do
        original_stderr = nil
        temp_file = Tempfile.new(%w[us_sdn_spec .zip])
        path = temp_file.path
        allow(Tempfile).to receive(:new).and_return(temp_file)
        allow(temp_file).to receive(:unlink).and_raise(
          Errno::EACCES, 'permission denied'
        )
        closed_stderr = StringIO.new
        closed_stderr.close
        original_stderr = $stderr
        # RSpec/ExpectOutput wants `output(...).to_stderr`, which captures a
        # working stream. The condition under test is a stream that is not
        # writable at all, which that matcher cannot express.
        $stderr = closed_stderr # rubocop:disable RSpec/ExpectOutput

        expect { extractor.fetch }.to raise_error(
          Ammitto::Error, /zip host unreachable/
        )
      ensure
        $stderr = original_stderr if original_stderr # rubocop:disable RSpec/ExpectOutput
        File.unlink(path) if path && File.exist?(path)
      end

      # Ordering, not just eventual removal: Tempfile#unlink drops the
      # pathname and leaves the descriptor open until GC, and on Windows --
      # which this gem tests on -- unlinking an open file raises. On Linux
      # the unlink succeeds either way, so nothing but the call order can
      # express this.
      it 'closes the handle before unlinking it' do
        temp_file = Tempfile.new(%w[us_sdn_spec .zip])
        allow(Tempfile).to receive(:new).and_return(temp_file)
        calls = []
        allow(temp_file).to receive(:close) { calls << :close }
        allow(temp_file).to receive(:unlink) { calls << :unlink }

        expect { extractor.fetch }.to raise_error(Ammitto::Error)
        expect(calls).to start_with(:close, :unlink)
      ensure
        temp_file.unlink if File.exist?(temp_file.path.to_s)
      end

      # The refusal message interpolates BOTH causes, so either of them
      # having a broken formatter escapes the same way -- and this path has
      # no fallback left to lose, it simply raises the wrong error out of
      # #fetch instead of the typed refusal.
      # Both halves are covered because the message interpolates both, and
      # guarding only one leaves the other able to escape.
      [described_class::SDN_ZIP_URL,
       described_class::LEGACY_SDN_URL].each do |broken_endpoint|
        it "refuses in kind when #{broken_endpoint} cannot describe itself" do
          broken = Class.new(StandardError) do
            def message = raise(NoMethodError, 'message formatter broke')
          end
          allow(URI).to receive(:open)
            .with(broken_endpoint, agent).and_raise(broken)

          expect { extractor.fetch }.to raise_error(
            Ammitto::Error, /message unavailable/
          )
        end
      end

      # The guard's own last interpolation. Naming the class is the
      # fallback when the message will not render, so a class that will not
      # render either has to terminate somewhere rather than raise out of
      # the handler.
      it 'refuses even when the error class will not render' do
        broken = Class.new(StandardError) do
          def message = raise(NoMethodError, 'message formatter broke')
        end
        def broken.to_s = raise(NoMethodError, 'class name broke')
        allow(URI).to receive(:open)
          .with(described_class::SDN_ZIP_URL, agent).and_raise(broken)

        expect { extractor.fetch }.to raise_error(
          Ammitto::Error, /unknown error \(message unavailable\)/
        )
      end

      it 'does not strand the temp file it opened for the download' do
        temp_file = Tempfile.new(['us_sdn_spec', '.zip'])
        path = temp_file.path
        allow(Tempfile).to receive(:new).and_return(temp_file)

        expect { extractor.fetch }.to raise_error(Ammitto::Error)
        expect(File.exist?(path)).to be(false)
      end
    end

    context 'when the archive holds no XML' do
      before do
        allow(URI).to receive(:open)
          .with(described_class::LEGACY_SDN_URL, agent)
          .and_raise(SocketError, 'legacy host unreachable')
        stub_zip_with(zip_bytes('readme.txt' => 'nothing useful here'))
      end

      # A 200 that carries the wrong archive is not a network fault, but it
      # is still a fetch that cannot produce data, and it must refuse the
      # same way rather than returning nil to the parser.
      it 'refuses instead of returning nil to the parser' do
        expect { extractor.fetch }.to raise_error(
          Ammitto::ParseError,
          /No XML file found in ZIP archive/
        )
      end

      # An archive that downloaded intact and carries the wrong members is
      # unusable content, not an unreachable endpoint: retrying will keep
      # succeeding and keep yielding nothing. Asserted as the exact class
      # because ParseError < Ammitto::Error, so the looser matcher cannot
      # tell the two refusals apart.
      it 'classifies it as unusable content, not a failed endpoint' do
        expect { extractor.fetch }.to(
          raise_error do |error|
            expect(error).to be_an_instance_of(Ammitto::ParseError)
            expect(error.format).to eq(:zip)
          end
        )
      end

      it 'still names the legacy failure that led here' do
        expect { extractor.fetch }.to raise_error(
          Ammitto::ParseError, /legacy host unreachable/
        )
      end
    end
  end
end
