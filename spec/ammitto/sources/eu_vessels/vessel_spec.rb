# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/eu_vessels/vessel'
require 'stringio'

RSpec.describe Ammitto::Sources::EuVessels::Vessel do
  describe '.from_row_data' do
    it 'parses a well-formed date_of_application' do
      vessel = described_class.from_row_data('date_of_application' => '2023-01-15')

      expect(vessel.date_of_application).to eq(Date.new(2023, 1, 15))
    end
  end

  # date_of_application discarded silently to nil before this change; the
  # published value must not change in any mode.
  describe 'parse failure visibility' do
    let(:io) { StringIO.new }

    before do
      Ammitto.reset_configuration!
      Ammitto::Logger.logger = Logger.new(io)
    end

    after do
      Ammitto::Logger.logger = nil
      ENV.delete('AMMITTO_PARSE_FAILURE_MODE')
    end

    it 'warns and counts, publishing nil exactly as before' do
      run = Ammitto::ParseFailureVisibility::Run.new
      vessel = nil

      Ammitto::ParseFailureVisibility.with_run(run) do
        vessel = described_class.from_row_data('date_of_application' => 'not-a-date')
      end

      expect(vessel.date_of_application).to be_nil
      expect(io.string).to include('Parse failure in eu_vessels.date_of_application')
      expect(run.count(:eu_vessels)).to eq(1)
    end

    it 'stays silent but still counts in silent mode' do
      Ammitto.configure { |config| config.parse_failure_mode = :silent }
      run = Ammitto::ParseFailureVisibility::Run.new
      vessel = nil

      Ammitto::ParseFailureVisibility.with_run(run) do
        vessel = described_class.from_row_data('date_of_application' => 'not-a-date')
      end

      expect(vessel.date_of_application).to be_nil
      expect(io.string).to be_empty
      expect(run.count(:eu_vessels)).to eq(1)
    end

    it 'raises Ammitto::ParseFailureError in raise mode' do
      Ammitto.configure { |config| config.parse_failure_mode = :raise }

      expect { described_class.parse_date('not-a-date') }
        .to raise_error(Ammitto::ParseFailureError) { |e|
          expect(e.source).to eq(:eu_vessels)
          expect(e.field).to eq(:date_of_application)
        }
    end
  end

  # Moved from spec/ammitto/cli/fetch/item_mapper_spec.rb along with the
  # candidate-priority logic itself: ItemMapper now just calls
  # `item.identifier`, so the fallback behaviour belongs on the class that
  # implements it. unique_identifier is "IMO-#{imo_number}", so it is
  # never blank even when imo_number is nil ("IMO-"); imo_number itself
  # is therefore always the value that actually wins in practice.
  describe '#identifier' do
    it 'is imo_number when present' do
      vessel = described_class.new(imo_number: '9999999')

      expect(vessel.identifier).to eq('9999999')
    end

    it 'falls through to unique_identifier when imo_number is blank' do
      vessel = described_class.new(imo_number: nil)

      expect(vessel.identifier).to eq('IMO-')
    end
  end
end
