# frozen_string_literal: true

require 'json'
require 'spec_helper'
require 'ammitto/serialization/birth_year_value'
require 'ammitto/serialization/birth_year_year'
require 'ammitto/serialization/birth_year_date_range'

RSpec.describe Ammitto::Serialization::BirthYear do
  describe Ammitto::Serialization::BirthYear::Year do
    it 'normalizes and renders an exact year' do
      value = described_class.new(1984)

      expect(value.value).to eq('1984')
      expect(value.exact?).to be true
      expect(value).to be_frozen
      expect(value.to_h).to eq(
        type: 'year',
        value: '1984',
        circa: false
      )
      expect(JSON.generate(value)).to eq(
        '{"type":"year","value":"1984","circa":false}'
      )
    end

    it 'keeps circa on the value itself' do
      value = described_class.new('1968', circa: true)

      expect(value.circa).to be true
      expect(value.exact?).to be false
    end

    it 'rejects malformed years' do
      expect { described_class.new('196') }.to raise_error(ArgumentError)
    end
  end

  describe Ammitto::Serialization::BirthYear::DateRange do
    it 'renders a closed range' do
      value = described_class.new(from: 1953, to: 1958)

      expect(value.to_h).to eq(
        type: 'date_range',
        from: '1953',
        to: '1958',
        circa: false
      )
    end

    it 'renders open bounds without losing direction' do
      expect(described_class.new(from: 1953).to_h).to eq(
        type: 'date_range',
        from: '1953',
        to: nil,
        circa: false
      )
      expect(described_class.new(to: 1980).to_h).to eq(
        type: 'date_range',
        from: nil,
        to: '1980',
        circa: false
      )
    end
  end
end
