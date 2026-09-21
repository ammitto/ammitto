# frozen_string_literal: true

require 'spec_helper'
require 'ammitto/sources/au'

RSpec.describe Ammitto::Sources::Au::Individual do
  describe '#merge_row date-of-birth deduplication' do
    def individual
      described_class.new(
        reference: 'dedup-test',
        dates_of_birth: [],
        places_of_birth: []
      )
    end

    it 'keeps one entry for a value repeated across comma-separated cells' do
      entity = individual
      entity.merge_row('Date of Birth' => '1990, 1990')

      expect(entity.dates_of_birth.map(&:year)).to eq([1990])
    end

    it 'keeps two entries that differ only by circa' do
      entity = individual
      entity.merge_row('Date of Birth' => 'Approximately 1990')
      entity.merge_row('Date of Birth' => '1990')

      expect(entity.dates_of_birth.size).to eq(2)
      expect(entity.dates_of_birth.map(&:circa)).to contain_exactly(true, nil)
    end

    it 'keeps two entries that differ only by year_range bounds' do
      entity = individual
      entity.merge_row('Date of Birth' => 'Approximately: Between 1959 and 1965')
      entity.merge_row('Date of Birth' => 'Approximately: Between 1960 and 1965')

      expect(entity.dates_of_birth.size).to eq(2)
    end
  end
end
