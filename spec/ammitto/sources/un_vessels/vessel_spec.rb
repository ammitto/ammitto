# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/un_vessels/vessel'

RSpec.describe Ammitto::Sources::UnVessels::Vessel do
  describe '.parse_date' do
    it 'parses a well-formed date' do
      expect(described_class.parse_date('2019-03-30')).to eq(Date.new(2019, 3, 30))
    end
  end

  # An unreadable designation_date publishes as nil in every mode;
  # visibility only adds the report.
  describe 'parse failure visibility' do
    include_context 'with parse failure log capture'

    it 'warns and counts, still publishing nil' do
      run = Ammitto::ParseFailureVisibility::Run.new
      result = nil

      Ammitto::ParseFailureVisibility.with_run(run) do
        result = described_class.parse_date('not-a-date')
      end

      expect(result).to be_nil
      expect(io.string).to include('Parse failure in un_vessels.designation_date')
      expect(run.count(:un_vessels)).to eq(1)
    end

    it 'stays silent but still counts in silent mode' do
      Ammitto.configure { |config| config.parse_failure_mode = :silent }
      run = Ammitto::ParseFailureVisibility::Run.new
      result = nil

      Ammitto::ParseFailureVisibility.with_run(run) do
        result = described_class.parse_date('not-a-date')
      end

      expect(result).to be_nil
      expect(io.string).to be_empty
      expect(run.count(:un_vessels)).to eq(1)
    end

    it 'raises Ammitto::ParseFailureError in raise mode' do
      Ammitto.configure { |config| config.parse_failure_mode = :raise }

      expect { described_class.parse_date('not-a-date') }
        .to raise_error(Ammitto::ParseFailureError) { |e|
          expect(e.source).to eq(:un_vessels)
          expect(e.field).to eq(:designation_date)
        }
    end
  end
end
