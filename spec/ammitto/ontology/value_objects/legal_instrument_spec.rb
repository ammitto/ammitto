# frozen_string_literal: true

require 'ammitto'
require 'ammitto/ontology'

RSpec.describe Ammitto::Ontology::ValueObjects::LegalInstrument do
  describe '#present?' do
    it 'requires an identifier or title' do
      expect(described_class.new(identifier: 'E.O. 14024')).to be_present
      expect(described_class.new(title: 'Some regulation')).to be_present
      expect(described_class.new(type: 'regulation')).not_to be_present
    end
  end

  describe '#type_sym' do
    it 'normalizes separator variants' do
      expect(described_class.new(type: 'Executive Order').type_sym).to eq(:executive_order)
      expect(described_class.new(type: 'regulation').type_sym).to eq(:regulation)
    end

    it 'falls back to :other' do
      expect(described_class.new(type: 'sky writing').type_sym).to eq(:other)
      expect(described_class.new.type_sym).to eq(:other)
    end
  end

  describe '#to_s' do
    it 'falls back identifier -> title -> placeholder' do
      expect(described_class.new(identifier: 'E.O. 14024', title: 'T').to_s).to eq('E.O. 14024')
      expect(described_class.new(title: 'T').to_s).to eq('T')
      expect(described_class.new.to_s).to eq('Unknown instrument')
    end
  end

  it 'round-trips through YAML with dates intact' do
    instrument = described_class.new(identifier: 'R 269/2014',
                                     publish_date: Date.new(2014, 3, 17))
    restored = described_class.from_yaml(instrument.to_yaml)
    expect(restored.identifier).to eq('R 269/2014')
    expect(restored.publish_date).to eq(Date.new(2014, 3, 17))
  end
end
