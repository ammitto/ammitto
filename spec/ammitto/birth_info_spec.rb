# frozen_string_literal: true

require 'spec_helper'

# The harmonized birth record. Its contract is that each field states
# exactly what the source stated: `date` one complete day-month-year,
# `year` one year, and the range bounds a span. A span never borrows
# either scalar, because neither bound is the birth year.
RSpec.describe Ammitto::BirthInfo do
  describe 'year range serialization' do
    let(:span) do
      described_class.new(year_range_from: 1959, year_range_to: 1965)
    end

    it 'publishes the bounds as camelCase JSON keys' do
      json = JSON.parse(span.to_json)

      expect(json['yearRangeFrom']).to eq(1959)
      expect(json['yearRangeTo']).to eq(1965)
    end

    it 'round-trips both bounds through JSON' do
      restored = described_class.from_json(span.to_json)

      expect(restored.year_range_from).to eq(1959)
      expect(restored.year_range_to).to eq(1965)
    end

    # YAML is the fetch artifact's format, so a bound that does not
    # survive it never reaches harmonize at all.
    it 'round-trips both bounds through YAML' do
      restored = described_class.from_yaml(span.to_yaml)

      expect(restored.year_range_from).to eq(1959)
      expect(restored.year_range_to).to eq(1965)
    end

    it 'round-trips a bound that stands alone' do
      open_above = described_class.new(year_range_from: 1953)
      restored = described_class.from_yaml(open_above.to_yaml)

      expect(restored.year_range_from).to eq(1953)
      expect(restored.year_range_to).to be_nil
    end
  end

  describe '#year_range?' do
    it 'is true for either bound alone, and false for neither' do
      expect(described_class.new(year_range_from: 1953)).to be_year_range
      expect(described_class.new(year_range_to: 1958)).to be_year_range
      expect(described_class.new(year: 1953)).not_to be_year_range
    end
  end

  describe '#formatted_date' do
    it 'renders a closed span as the span, not as either endpoint' do
      span = described_class.new(year_range_from: 1959, year_range_to: 1965)

      expect(span.formatted_date).to eq('1959-1965')
    end

    # An open bound must read as the direction it leaves open, or a
    # one-sided span would be indistinguishable from a closed one.
    it 'renders an open span as the direction it leaves open' do
      expect(described_class.new(year_range_from: 1953).formatted_date)
        .to eq('1953 or later')
      expect(described_class.new(year_range_to: 1958).formatted_date)
        .to eq('no later than 1958')
    end

    it 'still renders a single year and a complete date' do
      expect(described_class.new(year: 1964).formatted_date).to eq('1964')
      expect(described_class.new(date: Date.new(1964, 7, 17)).formatted_date)
        .to eq('1964-07-17')
    end
  end

  # The EU emits circa="true" and circa="false" alongside a span, so
  # circa is the source's own claim about the span, not a consequence of
  # there being one.
  describe 'circa independence' do
    it 'keeps circa false on a span by default' do
      span = described_class.new(year_range_from: 1960, year_range_to: 1962)

      expect(span.circa).to be false
      expect(span.formatted_date).to eq('1960-1962')
    end

    it 'carries circa true alongside a span' do
      span = described_class.new(year_range_from: 1953, year_range_to: 1958,
                                 circa: true)

      expect(span.circa).to be true
      expect(span.formatted_date).to eq('c. 1953-1958')
    end
  end
end
