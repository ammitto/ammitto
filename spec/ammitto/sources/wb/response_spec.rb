# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Sources::Wb::Response do
  # `of_json` goes through lutaml-model's own mapping, which reaches the
  # `ZPROCSUPP` custom method; the class-level `from_json` override does not.
  describe '.of_json' do
    it 'builds a SanctionedFirm for each ZPROCSUPP item' do
      response = described_class.of_json('ZPROCSUPP' => [{ 'SUPP_NAME' => 'Acme Ltd', 'SUPP_ID' => 7 }])

      expect(response.firms.map(&:supp_name)).to eq(['Acme Ltd'])
      expect(response.firms.map(&:supp_id)).to eq([7])
    end

    it 'unwraps a ZPROCSUPP hash nested under the ZPROCSUPP key' do
      response = described_class.of_json('ZPROCSUPP' => { 'ZPROCSUPP' => [{ 'SUPP_NAME' => 'Acme Ltd' }] })

      expect(response.firms.map(&:supp_name)).to eq(['Acme Ltd'])
    end

    ['not a list', { 'other' => [] }].each do |value|
      it "assigns an empty firm list for ZPROCSUPP #{value.inspect}" do
        expect(described_class.of_json('ZPROCSUPP' => value).firms).to eq([])
      end
    end

    # lutaml-model skips the custom method for a null value, leaving firms
    # unset; `items` is what every consumer reads.
    it 'yields no items for a null ZPROCSUPP' do
      expect(described_class.of_json('ZPROCSUPP' => nil).items).to eq([])
    end
  end

  describe '#to_json' do
    it 'writes each firm under ZPROCSUPP so the class-level from_json reads it back' do
      json = described_class.of_json('ZPROCSUPP' => [{ 'SUPP_NAME' => 'Acme Ltd', 'SUPP_ID' => 7 }]).to_json

      expect(JSON.parse(json)).to eq('ZPROCSUPP' => [{ 'SUPP_NAME' => 'Acme Ltd', 'SUPP_ID' => 7 }])
      expect(described_class.from_json(json).firms.map(&:supp_name)).to eq(['Acme Ltd'])
    end
  end
end
