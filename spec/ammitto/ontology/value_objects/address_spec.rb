# frozen_string_literal: true

require 'ammitto'

RSpec.describe Ammitto::Ontology::ValueObjects::Address do
  describe '#present? / #blank?' do
    it 'is present when any core field is set' do
      expect(described_class.new(city: 'Bern')).to be_present
      expect(described_class.new(street: '1 Main St')).to be_present
    end

    it 'is blank with no fields, and country_iso_code alone does not count' do
      expect(described_class.new).to be_blank
      expect(described_class.new(country_iso_code: 'CH')).to be_blank
    end
  end

  describe '#to_s' do
    it 'joins parts in street, city, region, postal code, country order' do
      address = described_class.new(street: '1 Main St', city: 'Bern',
                                    postal_code: '3000', country: 'Switzerland')
      expect(address.to_s).to eq('1 Main St, Bern, 3000, Switzerland')
    end
  end

  describe '#to_hash' do
    it 'omits nil fields' do
      expect(described_class.new(city: 'Bern').to_hash).to eq({ city: 'Bern' })
    end
  end

  it 'round-trips through YAML' do
    address = described_class.new(street: '1 Main St', city: 'Bern', country: 'Switzerland')
    restored = described_class.from_yaml(address.to_yaml)
    expect(restored.to_hash).to eq(address.to_hash)
  end
end
