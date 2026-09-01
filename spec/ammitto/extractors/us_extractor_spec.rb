# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'open-uri'
require 'ammitto/extractors/us_extractor'

RSpec.describe Ammitto::Extractors::UsExtractor do
  # OFAC publishes the SDN list twice: the flat sdn.xml this extractor
  # reads, and SDN_ADVANCED.ZIP in a different schema. #fetch used to try
  # the flat file and fall back to the archive.
  #
  # That fallback could not work. Measured against the live endpoint on
  # 2026-09-01: the archive expands to a 126 MB SDN_ADVANCED.XML rooted at
  # <Sanctions>, with zero <sdnList> or <sdnEntry> elements, and
  # SdnList.from_xml returns 0 entries from it after 288 seconds. So the
  # fallback spent five minutes turning a reachable file into nothing, and
  # it is gone. One endpoint, and a refusal when it cannot be read.
  subject(:extractor) { described_class.new }

  let(:agent) { { 'User-Agent' => described_class::USER_AGENT } }

  describe '#fetch' do
    it 'returns the list the source published' do
      allow(URI).to receive(:open)
        .with(described_class::SDN_URL, agent)
        .and_return(StringIO.new('<sdnList/>'))

      expect(extractor.fetch).to eq('<sdnList/>')
    end

    # treasury.gov serves 403 to the default Ruby agent, so the header is
    # part of the request rather than decoration.
    it 'sends the user agent the source requires' do
      allow(URI).to receive(:open).and_return(StringIO.new('<sdnList/>'))

      extractor.fetch

      expect(URI).to have_received(:open).with(described_class::SDN_URL, agent)
    end

    # BaseExtractor#verbose? also honours AMMITTO_VERBOSE. Reading the bare
    # `verbose` accessor instead left this source silent for an operator who
    # had set the env var and got progress from every other extractor.
    it 'honours AMMITTO_VERBOSE, not just the accessor' do
      allow(URI).to receive(:open).and_return(StringIO.new('<sdnList/>'))
      original = ENV.fetch('AMMITTO_VERBOSE', nil)
      ENV['AMMITTO_VERBOSE'] = 'true'

      expect { extractor.fetch }.to output(/Downloading SDN list/).to_stdout
    ensure
      ENV['AMMITTO_VERBOSE'] = original
    end

    context 'when the download fails' do
      before do
        allow(URI).to receive(:open).and_raise(SocketError, 'host unreachable')
      end

      it 'refuses, naming the cause and the endpoint' do
        expect { extractor.fetch }.to raise_error(
          Ammitto::NetworkError, /host unreachable/
        )
      end

      it 'does not reach for a second endpoint' do
        expect { extractor.fetch }.to raise_error(Ammitto::NetworkError)

        expect(URI).to have_received(:open).once
      end

      # An unguarded progress line would raise IOError on a closed $stdout,
      # reach #fetch's rescue, and be reported as a download failure. The
      # refusal has to name the download, not the log stream, or it sends
      # the operator after the wrong fault.
      it 'blames the download, not the log stream, when stdout is closed' do
        extractor.verbose = true
        closed = StringIO.new
        closed.close
        original = $stdout
        $stdout = closed # rubocop:disable RSpec/ExpectOutput

        expect { extractor.fetch }.to raise_error(
          Ammitto::NetworkError, /host unreachable/
        )
      ensure
        $stdout = original if original # rubocop:disable RSpec/ExpectOutput
      end
    end

    # The message interpolates the cause, and that interpolation runs before
    # the refusal is built.
    it 'refuses even when the error cannot describe itself' do
      broken = Class.new(StandardError) do
        def message = raise(NoMethodError, 'message formatter broke')
      end
      def broken.to_s = raise(NoMethodError, 'class name broke')
      allow(URI).to receive(:open).and_raise(broken)

      expect { extractor.fetch }.to raise_error(
        Ammitto::NetworkError, /unknown error/
      )
    end
  end
end
