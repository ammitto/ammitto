# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/nz/individual'

RSpec.describe Ammitto::Sources::Nz::Individual do
  describe '.from_row_data' do
    it 'parses a well-formed dob' do
      individual = described_class.from_row_data('dob' => '2012-06-29')

      expect(individual.dob).to eq(Date.new(2012, 6, 29))
    end
  end

  # An unreadable date publishes as nil in every mode; visibility only
  # adds the report of what the register actually said.
  describe 'parse failure visibility' do
    include_context 'with parse failure log capture'

    it 'warns and counts, still publishing nil' do
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

  # Moved from spec/ammitto/cli/fetch/item_mapper_spec.rb along with the
  # candidate-priority logic itself: ItemMapper now just calls
  # `item.identifier`, so the fallback behaviour belongs on the class that
  # implements it. reference_number is defined above as an alias of
  # unique_identifier, so the two candidates always agree; the fallback
  # is exercised anyway for parity with Entity and Ship.
  describe '#identifier' do
    it 'is unique_identifier when present' do
      individual = described_class.new(unique_identifier: 'NZ 12')

      expect(individual.identifier).to eq('NZ 12')
    end

    it 'is nil when unique_identifier is blank' do
      individual = described_class.new(unique_identifier: nil)

      expect(individual.identifier).to be_nil
    end
  end
end
