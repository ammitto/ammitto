# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/nz/ship'
require 'stringio'

RSpec.describe Ammitto::Sources::Nz::Ship do
  describe '.from_row_data' do
    it 'parses a well-formed date_of_sanction' do
      ship = described_class.from_row_data('date_of_sanction' => '2015-03-01')

      expect(ship.date_of_sanction).to eq(Date.new(2015, 3, 1))
    end
  end

  # Same discard-then-vanish shape as Individual, on the vessel side of
  # the register.
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
      ship = nil

      Ammitto::ParseFailureVisibility.with_run(run) do
        ship = described_class.from_row_data('date_of_sanction' => 'not-a-date')
      end

      expect(ship.date_of_sanction).to be_nil
      expect(io.string).to include('Parse failure in nz.date_of_sanction')
      expect(run.count(:nz)).to eq(1)
    end

    it 'stays silent but still counts in silent mode' do
      Ammitto.configure { |config| config.parse_failure_mode = :silent }
      run = Ammitto::ParseFailureVisibility::Run.new
      ship = nil

      Ammitto::ParseFailureVisibility.with_run(run) do
        ship = described_class.from_row_data('date_record_deleted' => 'not-a-date')
      end

      expect(ship.date_record_deleted).to be_nil
      expect(io.string).to be_empty
      expect(run.count(:nz)).to eq(1)
    end

    it 'raises Ammitto::ParseFailureError in raise mode' do
      Ammitto.configure { |config| config.parse_failure_mode = :raise }

      expect { described_class.parse_date('not-a-date', field: :date_record_deleted) }
        .to raise_error(Ammitto::ParseFailureError) { |e|
          expect(e.source).to eq(:nz)
          expect(e.field).to eq(:date_record_deleted)
        }
    end
  end
end
