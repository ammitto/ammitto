# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Sources::Wb::Transformer do
  let(:transformer) { described_class.new }

  describe '#source_code' do
    it 'returns :wb' do
      expect(transformer.source_code).to eq(:wb)
    end
  end

  describe '#authority' do
    it 'returns WB authority' do
      auth = transformer.send(:authority)
      expect(auth.id).to eq('wb')
      expect(auth.name).to eq('World Bank')
    end
  end

  # An unreadable debar_from_date or debar_to_date publishes as nil in
  # every mode; visibility only adds the report.
  describe 'parse failure visibility for debarment dates' do
    include_context 'with parse failure log capture'

    let(:firm) do
      Ammitto::Sources::Wb::SanctionedFirm.new(
        supp_id: 1,
        supp_name: 'Example Firm',
        supp_type_code: 'O',
        debar_from_date: 'not-a-date',
        debar_to_date: '2099-01-01'
      )
    end

    let(:parse_unreadable) { -> { transformer.transform(firm)[:entry].period.effective_date } }
    let(:raise_unreadable) { -> { transformer.send(:parse_wb_date, 'not-a-date', field: :debar_from_date) } }

    it_behaves_like 'a reported parse failure', source: :wb, field: :debar_from_date

    it 'leaves is_indefinite unasserted for an unreadable debar_to_date and reports it once as expiry_date' do
      firm.debar_from_date = '2020-01-01'
      firm.debar_to_date = 'not-a-date'
      result = count_parse_failures { transformer.transform(firm) }

      expect(result[:entry].period.expiry_date).to be_nil
      expect(result[:entry].period.is_indefinite).to be_nil
      expect(io.string.scan('Parse failure in wb.expiry_date').size).to eq(1)
      expect(run.count(:wb)).to eq(1)
    end
  end
end
