# frozen_string_literal: true

require 'ammitto'
require 'ammitto/ontology'

RSpec.describe Ammitto::Ontology::ValueObjects::BirthInfo do
  describe '#birth_year' do
    it 'prefers the full date over the bare year' do
      info = described_class.new(date: Date.new(1964, 7, 17), year: 1999)
      expect(info.birth_year).to eq(1964)
    end

    it 'falls back to the bare year, then nil' do
      expect(described_class.new(year: 1964).birth_year).to eq(1964)
      expect(described_class.new.birth_year).to be_nil
    end
  end

  describe '#present?' do
    it 'counts date, year, city, or country' do
      expect(described_class.new(year: 1964)).to be_present
      expect(described_class.new(city: 'Bern')).to be_present
      expect(described_class.new(region: 'BE')).not_to be_present
    end
  end

  describe '#to_s' do
    it 'renders exact output with and without circa' do
      expect(described_class.new(year: 1964, circa: true).to_s).to eq('c. 1964')
      expect(described_class.new(year: 1964).to_s).to eq('1964')
    end

    it 'appends the place exactly, with no stray spacing' do
      info = described_class.new(date: Date.new(1964, 7, 17), city: 'Bern', country: 'CH')
      expect(info.to_s).to eq('1964-07-17 Bern, CH')
    end
  end

  describe '#to_hash' do
    it 'omits the default circa=false' do
      expect(described_class.new(year: 1964).to_hash).to eq({ year: 1964 })
    end
  end
end
