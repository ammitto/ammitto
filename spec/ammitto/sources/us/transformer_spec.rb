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

    # "YYYY to YYYY" is the only bare year-span spelling OFAC uses: 52
    # of the 5795 distinct dateOfBirth values in the live SDN export
    # take that shape, and none takes a hyphenated one.
    it 'reads a year span into the range bounds, leaving both scalars nil' do
      birth = birth_for('1962 to 1964')
      expect(birth.year_range_from).to eq(1962)
      expect(birth.year_range_to).to eq(1964)
      expect(birth.date).to be_nil
      expect(birth.year).to be_nil
    end

    it 'does not mark a span circa: OFAC states these bounds exactly' do
      expect(birth_for('1962 to 1964').circa).to be false
    end

    # KNOWN GAP, deliberate. A full-date span carries day precision that
    # year bounds cannot hold, and the harmonized contract has no
    # date-valued range, so such a record publishes nothing at all.
    # Reducing it to 1962-1964 would discard the days and months the
    # source did state; asserting its opening date, which this
    # transformer used to do, invented a single date the source never
    # stated. Of the 117 spans in the live SDN export, 65 are of this
    # finer-precision kind.
    it 'publishes nothing for a full-date span rather than its opening date' do
      birth = birth_for('28 Feb 1962 to 28 Feb 1963')
      expect(birth.date).to be_nil
      expect(birth.year).to be_nil
      expect(birth.year_range_from).to be_nil
      expect(birth.year_range_to).to be_nil
    end

    # The costliest case of that gap, and the reason the opening date had
    # to go: OFAC writes "01 Jan YYYY to 31 Dec YYYY" 37 distinct ways to
    # mean "some day that year". Reading it as 1 January asserted the
    # invented January date this gem set out to stop asserting.
    #
    # The year survives, though. Both endpoints state 1973 and the whole
    # interval lies inside it, so discarding the year to avoid the false
    # day would throw away a certainly-true fact about a sanctioned
    # person. All four fields are asserted because getting the day right
    # and the bounds wrong would be just as much a defect.
    it 'keeps the stated year of a whole-year span without its 1 January date' do
      birth = birth_for('01 Jan 1973 to 31 Dec 1973')
      expect(birth.date).to be_nil
      expect(birth.year).to eq(1973)
      expect(birth.year_range_from).to be_nil
      expect(birth.year_range_to).to be_nil
    end

    it 'still resolves an ordinary date that merely contains a month name' do
      expect(birth_for('28 Feb 1962').date).to eq(Date.new(1962, 2, 28))
    end
  end
end
