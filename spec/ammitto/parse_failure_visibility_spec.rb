# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe Ammitto::ParseFailureVisibility do
  let(:io) { StringIO.new }

  before do
    Ammitto.reset_configuration!
    Ammitto::Logger.logger = Logger.new(io)
  end

  after do
    Ammitto::Logger.logger = nil
    ENV.delete('AMMITTO_PARSE_FAILURE_MODE')
    # 'rejects an invalid mode' leaves the global configuration on :bogus;
    # left unreset, that mode leaks into any later spec anywhere in the
    # suite that exercises ParseFailureVisibility.report through a source
    # parser, since #mode reads Ammitto.configuration directly.
    Ammitto.reset_configuration!
  end

  it 'defaults to warn' do
    run = described_class::Run.new

    expect do
      described_class.with_run(run) do
        described_class.report(
          source: :nz,
          field: :dob,
          value: 'not-a-date'
        )
      end
    end.not_to raise_error

    expect(io.string).to include('Parse failure in nz.dob')
    expect(run.count(:nz)).to eq(1)
  end

  it 'supports silent mode while retaining the count' do
    Ammitto.configure { |config| config.parse_failure_mode = :silent }
    run = described_class::Run.new

    described_class.with_run(run) do
      described_class.report(
        source: :nz,
        field: :dob,
        value: 'not-a-date'
      )
    end

    expect(io.string).to be_empty
    expect(run.count(:nz)).to eq(1)
  end

  it 'raises a typed error in raise mode' do
    Ammitto.configure { |config| config.parse_failure_mode = :raise }
    run = described_class::Run.new

    raised = nil
    begin
      described_class.with_run(run) do
        described_class.report(
          source: :nz,
          field: :dob,
          value: 'not-a-date'
        )
      end
    rescue Ammitto::ParseFailureError => e
      raised = e
    end

    expect(raised).to be_a(Ammitto::ParseFailureError)
    expect(raised.source).to eq(:nz)
    expect(raised.field).to eq(:dob)
    expect(raised.value).to eq('not-a-date')
    expect(run.count(:nz)).to eq(1)
  end

  it 'prefers ENV over the programmatic setting' do
    Ammitto.configure { |config| config.parse_failure_mode = :silent }
    ENV['AMMITTO_PARSE_FAILURE_MODE'] = 'raise'

    expect(described_class.mode).to eq(:raise)
  end

  it 'rejects an invalid mode' do
    Ammitto.configure { |config| config.parse_failure_mode = :bogus }

    expect { described_class.mode }
      .to raise_error(Ammitto::ConfigurationError)
  end
end
