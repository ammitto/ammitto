# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/eu_vessels/vessel'

RSpec.describe Ammitto::Sources::EuVessels::Vessel do
  describe '.from_row_data' do
    it 'parses a well-formed date_of_application' do
      vessel = described_class.from_row_data('date_of_application' => '2023-01-15')

      expect(vessel.date_of_application).to eq(Date.new(2023, 1, 15))
    end
  end

  # An unreadable date_of_application publishes as nil in every mode;
  # visibility only adds the report.
  describe 'parse failure visibility' do
    include_context 'with parse failure log capture'

    let(:parse_unreadable) do
      -> { described_class.from_row_data('date_of_application' => 'not-a-date').date_of_application }
    end
    let(:raise_unreadable) { -> { described_class.parse_date('not-a-date') } }

    it_behaves_like 'a reported parse failure', source: :eu_vessels, field: :date_of_application
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
