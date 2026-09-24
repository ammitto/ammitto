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

  # Moved from spec/ammitto/cli/fetch/item_mapper_spec.rb along with the
  # candidate-priority logic itself: ItemMapper now just calls
  # `item.identifier`, so the fallback behaviour belongs on the class that
  # implements it.
  #
  # The task this spec was written for described a suspected latent bug:
  # that Ship might not define reference_number at all, so the old
  # `[item.unique_identifier, item.reference_number]` candidate list would
  # raise NoMethodError rather than return nil for a real Ship with a
  # blank unique_identifier. Reading this file shows that is NOT the
  # case on this branch — Ship defines reference_number as an alias of
  # unique_identifier, same as Individual and Entity — so there is no
  # live bug to fix here. This spec exists anyway, to lock in that Ship
  # answers #identifier the same way its siblings do and never raises,
  # and to catch it if reference_number is ever removed from this file
  # without reference_number's caller here being updated to match.
  describe '#identifier' do
    it 'is unique_identifier when present' do
      ship = described_class.new(unique_identifier: 'NZ-SHIP-1')

      expect(ship.identifier).to eq('NZ-SHIP-1')
    end

    it 'returns nil rather than raising when unique_identifier is blank' do
      ship = described_class.new(unique_identifier: nil)

      expect { ship.identifier }.not_to raise_error
      expect(ship.identifier).to be_nil
    end
  end
end
