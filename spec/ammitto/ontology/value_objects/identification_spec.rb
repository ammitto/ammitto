# frozen_string_literal: true

require 'ammitto'

RSpec.describe Ammitto::Ontology::ValueObjects::Identification do
  describe '#present?' do
    it 'depends on the number alone' do
      expect(described_class.new(number: 'P-123')).to be_present
      expect(described_class.new(type: 'passport')).not_to be_present
    end
  end

  describe '#type_sym' do
    it 'normalizes known variants' do
      expect(described_class.new(type: 'Passports').type_sym).to eq(:passport)
      expect(described_class.new(type: 'national id').type_sym).to eq(:national_id)
    end

    it 'falls back to :other for unknown or missing types' do
      expect(described_class.new(type: 'carrier pigeon').type_sym).to eq(:other)
      expect(described_class.new.type_sym).to eq(:other)
    end
  end

  describe '#to_hash' do
    it 'stringifies dates and omits nils' do
      id = described_class.new(number: 'P-123', expiry_date: Date.new(2030, 1, 2))
      expect(id.to_hash).to eq({ number: 'P-123', expiry_date: '2030-01-02' })
    end
  end

  it 'round-trips through YAML with date types intact' do
    id = described_class.new(type: 'passport', number: 'P-123',
                             issue_date: Date.new(2020, 5, 1))
    restored = described_class.from_yaml(id.to_yaml)
    expect(restored.number).to eq('P-123')
    expect(restored.issue_date).to eq(Date.new(2020, 5, 1))
  end
end
