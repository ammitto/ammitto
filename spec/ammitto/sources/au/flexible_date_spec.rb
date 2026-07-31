# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/au'

RSpec.describe Ammitto::Sources::Au::FlexibleDate do
  describe '.parse' do
    it 'parses full date "5 May 1957"' do
      date = described_class.parse('5 May 1957')
      expect(date.year).to eq(1957)
      expect(date.month).to eq(5)
      expect(date.day).to eq(5)
      expect(date.precision).to eq('full')
    end

    it 'parses month/year "May 1957"' do
      date = described_class.parse('May 1957')
      expect(date.year).to eq(1957)
      expect(date.month).to eq(5)
      expect(date.day).to be_nil
      expect(date.precision).to eq('month')
    end

    it 'parses year only "1957"' do
      date = described_class.parse('1957')
      expect(date.year).to eq(1957)
      expect(date.precision).to eq('year')
    end

    it 'parses circa date "circa 1957"' do
      date = described_class.parse('circa 1957')
      expect(date.year).to eq(1957)
      expect(date.circa).to be true
      expect(date.precision).to eq('circa')
    end

    it 'returns nil for empty string' do
      expect(described_class.parse('')).to be_nil
    end

    it 'returns nil for nil' do
      expect(described_class.parse(nil)).to be_nil
    end
  end

  describe '#to_date' do
    it 'converts to Date object' do
      date = described_class.parse('5 May 1957')
      expect(date.to_date).to eq(Date.new(1957, 5, 5))
    end
  end
end
