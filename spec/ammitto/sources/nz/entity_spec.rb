# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/nz/entity'

RSpec.describe Ammitto::Sources::Nz::Entity do
  # An unreadable date publishes as nil in every mode; visibility only
  # adds the report of what the register actually said.
  describe 'parse failure visibility' do
    include_context 'with parse failure log capture'

    let(:parse_unreadable) do
      -> { described_class.from_row_data('date_of_sanction' => 'not-a-date').date_of_sanction }
    end
    let(:raise_unreadable) do
      -> { described_class.from_row_data('date_of_additional_sanction' => 'not-a-date') }
    end

    it_behaves_like 'a reported parse failure', source: :nz, field: :date_of_sanction,
                                                raised_field: :date_of_additional_sanction,
                                                raised_value: 'not-a-date'

    it 'returns nil and reports nothing for an unreadable value given no field' do
      expect(count_parse_failures { described_class.parse_date('not-a-date') }).to be_nil
      expect(run.count(:nz)).to eq(0)
    end

    it 'does not report a value that parsed cleanly' do
      entity = count_parse_failures { described_class.from_row_data('date_of_sanction' => '2012-06-29') }

      expect(entity.date_of_sanction).to eq(Date.new(2012, 6, 29))
      expect(run.count(:nz)).to eq(0)
    end
  end

  # Moved from spec/ammitto/cli/fetch/item_mapper_spec.rb along with the
  # candidate-priority logic itself: ItemMapper now just calls
  # `item.identifier`, so the fallback behaviour belongs on the class that
  # implements it. reference_number is defined above as an alias of
  # unique_identifier, so the two candidates always agree; the fallback
  # is exercised anyway for parity with Individual and Ship.
  describe '#identifier' do
    it 'is unique_identifier when present' do
      entity = described_class.new(unique_identifier: 'NZ 34')

      expect(entity.identifier).to eq('NZ 34')
    end

    it 'is nil when unique_identifier is blank' do
      entity = described_class.new(unique_identifier: nil)

      expect(entity.identifier).to be_nil
    end
  end
end
