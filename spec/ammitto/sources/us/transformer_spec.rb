# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Sources::Us::Transformer do
  let(:transformer) { described_class.new }

  describe '#source_code' do
    it 'returns :us' do
      expect(transformer.source_code).to eq(:us)
    end
  end

  describe '#authority' do
    it 'returns US authority' do
      auth = transformer.send(:authority)
      expect(auth.id).to eq('us')
      expect(auth.name).to eq('United States (OFAC)')
    end
  end

  # The birth-precision invariant: a source-provided year is
  # BirthInfo#year; BirthInfo#date is set only when the source states a
  # complete day-month-year.
  describe '#transform_birth_info' do
    def birth_for(dob_string)
      entry = Ammitto::Sources::Us::SdnEntry.new(
        uid: '1',
        date_of_birth_list: Ammitto::Sources::Us::DateOfBirthList.new(
          items: [
            Ammitto::Sources::Us::DateOfBirthItem.new(date_of_birth: dob_string)
          ]
        )
      )
      transformer.send(:transform_birth_info, entry).first
    end

    it 'keeps a bare year as year, without a date' do
      birth = birth_for('1988')
      expect(birth.year).to eq(1988)
      expect(birth.date).to be_nil
    end

    it 'keeps a month-year DOB as year, without inventing day 1' do
      birth = birth_for('Oct 1988')
      expect(birth.year).to eq(1988)
      expect(birth.date).to be_nil
    end

    it 'keeps a circa year as a circa-flagged year, without a date' do
      birth = birth_for('circa 1960')
      expect(birth.year).to eq(1960)
      expect(birth.date).to be_nil
      expect(birth.circa).to be true
    end

    it 'resolves a complete DOB to a date plus year' do
      birth = birth_for('03 Oct 1988')
      expect(birth.date).to eq(Date.new(1988, 10, 3))
      expect(birth.year).to eq(1988)
    end

    # Range handling is deliberately deferred (separate design); these
    # pin today's behavior so a later range design changes it knowingly.
    it 'pins year ranges to no date and no year, pending range handling' do
      birth = birth_for('1962 to 1964')
      expect(birth.date).to be_nil
      expect(birth.year).to be_nil
    end

    it 'pins full-date ranges to their opening date, pending range handling' do
      birth = birth_for('28 Feb 1962 to 28 Feb 1963')
      expect(birth.date).to eq(Date.new(1962, 2, 28))
      expect(birth.year).to eq(1962)
    end
  end
end
