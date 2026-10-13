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

  describe '#transform with register and creation fields' do
    include_context 'with World Bank fixture firms'

    # Harmonize reads the processed YAML, so the firms take that route.
    let(:results) do
      firms.transform_values do |firm|
        transformer.transform(Ammitto::Sources::Wb::SanctionedFirm.from_yaml(firm.to_yaml))
      end
    end

    it 'publishes REGISTER_ID as an identification on an organization' do
      ids = results[407_985][:entity].identifications
      expect(ids.map { |i| [i.type, i.number] }).to eq([['Register ID', '0102133351']])
    end

    it 'publishes REGISTER_ID as stated on an individual' do
      ids = results[666_304][:entity].identifications
      expect(ids.map(&:number)).to eq(['00018161'])
    end

    it 'publishes no identification when REGISTER_ID is empty' do
      expect(results[573_628][:entity].identifications).to eq([])
    end

    it 'does not present the record creation date as a listing date' do
      expect(results[407_985][:entry].period.listed_date).to be_nil
      expect(results[407_985][:entry].period.effective_date).to eq(Date.new(2019, 8, 2))
    end

    it 'keeps the fields without an ontology home in the raw source data' do
      fields = results[407_985][:entry].raw_source_data.source_specific_fields
      expect(fields).to include(
        'wb:parent' => 'N', 'wb:rechkInd' => 'N', 'wb:createUser' => '9000060495',
        'wb:createUserName' => 'Ho Quang Phuc', 'wb:createDate' => '2021-08-03T00:00:00.000Z'
      )
      expect(results[939_357][:entry].raw_source_data.source_specific_fields['wb:register']).to eq('Y')
      expect(results[311_048][:entry].raw_source_data.source_specific_fields['wb:amlEntrInd']).to eq('S')
    end
  end
end
