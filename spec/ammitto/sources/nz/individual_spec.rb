# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/nz/individual'
require 'stringio'

RSpec.describe Ammitto::Sources::Nz::Individual do
  describe '.from_row_data' do
    it 'parses a well-formed dob' do
      individual = described_class.from_row_data('dob' => '2012-06-29')

      expect(individual.dob).to eq(Date.new(2012, 6, 29))
    end
  end

  # An unparseable date currently vanishes into nil with no trace of what
  # the register actually said. Visibility is additive: the published
  # value (nil, same as before) must not change in any mode.
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
      individual = nil

      Ammitto::ParseFailureVisibility.with_run(run) do
        individual = described_class.from_row_data('dob' => 'not-a-date')
      end

      expect(individual.dob).to be_nil
      expect(io.string).to include('Parse failure in nz.dob')
      expect(run.count(:nz)).to eq(1)
    end

    it 'stays silent but still counts in silent mode' do
      Ammitto.configure { |config| config.parse_failure_mode = :silent }
      run = Ammitto::ParseFailureVisibility::Run.new
      individual = nil

      Ammitto::ParseFailureVisibility.with_run(run) do
        individual = described_class.from_row_data('dob' => 'not-a-date')
      end

      expect(individual.dob).to be_nil
      expect(io.string).to be_empty
      expect(run.count(:nz)).to eq(1)
    end

    it 'raises Ammitto::ParseFailureError in raise mode' do
      Ammitto.configure { |config| config.parse_failure_mode = :raise }

      expect { described_class.parse_date('not-a-date', field: :dob) }
        .to raise_error(Ammitto::ParseFailureError) { |e|
          expect(e.source).to eq(:nz)
          expect(e.field).to eq(:dob)
          expect(e.value).to eq('not-a-date')
        }
    end

    it 'reports each date field under its own name' do
      run = Ammitto::ParseFailureVisibility::Run.new

      Ammitto::ParseFailureVisibility.with_run(run) do
        described_class.parse_date('bogus', field: :date_of_sanction)
      end

      expect(run.count(:nz)).to eq(1)
      expect(io.string).to include('Parse failure in nz.date_of_sanction')
    end

    it 'does not report a value that parsed cleanly' do
      run = Ammitto::ParseFailureVisibility::Run.new

      Ammitto::ParseFailureVisibility.with_run(run) do
        described_class.parse_date('2012-06-29', field: :dob)
      end

      expect(run.count(:nz)).to eq(0)
    end
  end
end
