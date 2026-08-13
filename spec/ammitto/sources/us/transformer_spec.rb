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

    # A month-precision span keeps its years and loses its months. Date
    # bounds cannot hold it without inventing a day, so the alternative
    # is publishing nothing, which is what this shape did before: the
    # "Mon YYYY to Mon YYYY" records in the SDN export fell through both
    # recognizers — too coarse for the full-date span, too fine for the
    # anchored bare-year one.
    it 'reads a month span into the year bounds rather than publishing nothing' do
      birth = birth_for('Mar 1962 to Feb 1963')
      expect(birth.year_range_from).to eq(1962)
      expect(birth.year_range_to).to eq(1963)
      expect(birth.date_range_from).to be_nil
      expect(birth.date).to be_nil
      expect(birth.year).to be_nil
    end

    # A single month-and-year is a point, not a span, and still yields
    # the stated year as a scalar.
    it 'leaves a lone month and year as a scalar year' do
      expect(birth_for('Aug 1946').year).to eq(1946)
    end

    # The gap this used to record is closed. A full-date span carries
    # day precision that year bounds cannot hold, and the contract now
    # has a date-valued range to hold it, so the record no longer has to
    # choose between discarding the days and publishing its opening date
    # as though the source had stated it alone. This is the majority of
    # the spans in the SDN export. The endpoint years go out too, for
    # the year-only search index; they supplement the complete claim
    # rather than replacing it.
    it 'publishes a full-date span without replacing it with its opening date' do
      birth = birth_for('28 Feb 1962 to 28 Feb 1963')
      json = JSON.parse(birth.to_json)

      expect(json['dateRangeFrom']).to eq('1962-02-28')
      expect(json['dateRangeTo']).to eq('1963-02-28')
      expect(json['yearRangeFrom']).to eq(1962)
      expect(json['yearRangeTo']).to eq(1963)
      # Absent, not published as null: a consumer reading `date` off this
      # record must find nothing there, and `be_nil` would pass just as
      # happily on an explicit null that had re-asserted an opening date
      # of sorts.
      expect(json).not_to have_key('date')
      expect(json).not_to have_key('year')
    end

    # The costliest case, and the reason the opening date had to go:
    # OFAC writes "01 Jan YYYY to 31 Dec YYYY" in dozens of spellings to
    # mean "some day that year". Reading it as 1 January asserted the
    # invented January date this gem set out to stop asserting.
    #
    # Both complete endpoints still matter even when they share a year.
    # The scalar year survives because the whole interval lies inside
    # it, while the equal year bounds keep every date span in the same
    # search path.
    it 'keeps the exact year alongside a same-year full-date span' do
      birth = birth_for('01 Jan 1973 to 31 Dec 1973')
      json = JSON.parse(birth.to_json)

      expect(json['dateRangeFrom']).to eq('1973-01-01')
      expect(json['dateRangeTo']).to eq('1973-12-31')
      expect(json['year']).to eq(1973)
      expect(json['yearRangeFrom']).to eq(1973)
      expect(json['yearRangeTo']).to eq(1973)
      expect(json).not_to have_key('date')
    end

    it 'still resolves an ordinary date that merely contains a month name' do
      expect(birth_for('28 Feb 1962').date).to eq(Date.new(1962, 2, 28))
    end
  end
end
