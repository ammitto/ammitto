# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Sources::Ch::Transformer do
  let(:transformer) { described_class.new }

  describe '#source_code' do
    it 'returns :ch' do
      expect(transformer.source_code).to eq(:ch)
    end
  end

  describe '#authority' do
    it 'returns CH authority' do
      auth = transformer.send(:authority)
      expect(auth.id).to eq('ch')
      expect(auth.name).to eq('Switzerland (SECO)')
    end
  end

  # The birth-precision invariant: a source-provided year is
  # BirthInfo#year; BirthInfo#date is set only when the source states a
  # complete day-month-year.
  describe '#transform_birth_info' do
    def birth_for(day: nil, month: nil, year: nil)
      identity = Ammitto::Sources::Ch::Identity.new(
        ssid: '100',
        day_month_year: Ammitto::Sources::Ch::DayMonthYear.new(
          day: day, month: month, year: year
        )
      )
      transformer.send(:transform_birth_info, identity).first
    end

    it 'keeps a year-only record as year, without a date' do
      birth = birth_for(year: 1975)
      expect(birth.year).to eq(1975)
      expect(birth.date).to be_nil
    end

    it 'keeps a year-month record as year, without inventing a day' do
      birth = birth_for(year: 1975, month: 3)
      expect(birth.year).to eq(1975)
      expect(birth.date).to be_nil
    end

    it 'resolves a fully stated record to a date plus year' do
      birth = birth_for(year: 1975, month: 3, day: 5)
      expect(birth.date).to eq(Date.new(1975, 3, 5))
      expect(birth.year).to eq(1975)
    end
  end
end
