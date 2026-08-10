# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ammitto::Transformers::BaseTransformer do
  let(:transformer) { described_class.new(:test) }

  describe '#source_code' do
    it 'returns the source code' do
      expect(transformer.source_code).to eq(:test)
    end
  end

  describe '#transform' do
    it 'raises NotImplementedError' do
      expect { transformer.transform({}) }.to raise_error(NotImplementedError)
    end
  end

  describe '#generate_entity_id' do
    it 'generates a LIST-AGNOSTIC entity URI (sanitized to lowercase)' do
      id = transformer.send(:generate_entity_id, 'TEST123')
      # Entity IRIs are list-agnostic (no list_type) and sanitized to lowercase
      expect(id).to eq('https://www.ammitto.org/entity/test/test123')
    end
  end

  describe '#generate_entry_id' do
    it 'generates a LIST-SPECIFIC entry URI' do
      id = transformer.send(:generate_entry_id, 'TEST123')
      # Entry IRIs are list-specific and include list_type
      # For unknown source like :test, default_list_type returns nil which becomes 'unknown'
      expect(id).to eq('https://www.ammitto.org/entry/test/unknown/test123')
    end

    it 'allows list_type override' do
      id = transformer.send(:generate_entry_id, 'TEST123', entry_list_type: 'consolidated-list')
      expect(id).to eq('https://www.ammitto.org/entry/test/consolidated-list/test123')
    end
  end

  describe '#authority' do
    it 'returns the authority for the source' do
      auth = transformer.send(:authority)
      expect(auth).to be_nil # :test is not a registered authority
    end
  end

  # The birth-precision invariant: a source-provided year is BirthInfo#year;
  # BirthInfo#date is set only when the source states a complete
  # day-month-year, never padded from a partial expression.
  describe '#create_birth_info' do
    it 'sets date and year for a complete date string' do
      info = transformer.send(:create_birth_info, date: '03 Oct 1988')
      expect(info.date).to eq(Date.new(1988, 10, 3))
      expect(info.year).to eq(1988)
    end

    it 'keeps a bare year as year only, without inventing a date' do
      info = transformer.send(:create_birth_info, date: '1988')
      expect(info.date).to be_nil
      expect(info.year).to eq(1988)
    end

    it 'keeps a month-year string as year only, without inventing a day' do
      info = transformer.send(:create_birth_info, date: 'Oct 1988')
      expect(info.date).to be_nil
      expect(info.year).to eq(1988)
    end

    it 'prefers an explicitly passed year over string extraction' do
      info = transformer.send(:create_birth_info, date: nil, year: 1971)
      expect(info.date).to be_nil
      expect(info.year).to eq(1971)
    end

    it 'passes a caller-resolved Date through unchanged' do
      info = transformer.send(:create_birth_info, date: Date.new(1957, 5, 5))
      expect(info.date).to eq(Date.new(1957, 5, 5))
      expect(info.year).to eq(1957)
    end
  end

  # A span of years is not a year. It rides in its own two fields, and
  # while it is there neither scalar may hold one of its endpoints:
  # there is no honest single value to publish, and a consumer reading
  # the lower bound as the birth year would be reading a fact the source
  # never stated.
  describe '#create_birth_info with a year range' do
    def birth(**args)
      transformer.send(:create_birth_info, **args)
    end

    it 'reads a closed span into the bounds and clears both scalars' do
      info = birth(date: '1962 to 1964')

      expect(info.year_range_from).to eq(1962)
      expect(info.year_range_to).to eq(1964)
      expect(info.year).to be_nil
      expect(info.date).to be_nil
    end

    it 'leaves an exact year in year, with no span' do
      info = birth(date: '1988')

      expect(info.year).to eq(1988)
      expect(info.year_range_from).to be_nil
      expect(info.year_range_to).to be_nil
    end

    it 'takes caller-stated bounds, as the EU states them' do
      info = birth(year_range_from: 1953, year_range_to: 1958)

      expect(info.year_range_from).to eq(1953)
      expect(info.year_range_to).to eq(1958)
    end

    # The EU corpus carries one record with only an upper bound, so a
    # lone bound must survive rather than being discarded or paired off.
    it 'keeps a bound that stands alone on either side' do
      expect(birth(year_range_to: 1980).year_range_to).to eq(1980)
      expect(birth(year_range_to: 1980).year_range_from).to be_nil
      expect(birth(year_range_from: 1953).year_range_from).to eq(1953)
      expect(birth(year_range_from: 1953).year_range_to).to be_nil
    end

    it 'suppresses a caller-stated year when a span is also stated' do
      info = birth(date: '1955', year: 1955,
                   year_range_from: 1953, year_range_to: 1958)

      expect(info.year).to be_nil
      expect(info.date).to be_nil
      expect(info.year_range_from).to eq(1953)
    end

    it 'keeps the place on a span, so the record is not emptied' do
      info = birth(date: '1962 to 1964', city: 'Kandahar', country: 'AFGHANISTAN')

      expect(info.city).to eq('Kandahar')
      expect(info.country).to eq('AFGHANISTAN')
    end

    # circa is the source's claim about the span, not a consequence of
    # there being one: the EU emits both settings alongside a span.
    it 'carries circa through a span in both settings' do
      expect(birth(date: '1962 to 1964').circa).to be false
      expect(birth(date: 'Approximately: Between 1959 and 1965',
                   circa: true).circa).to be true
    end

    it 'reads the Between spelling, with and without the prefix' do
      ['Between', 'Approximately: Between'].each do |prefix|
        info = birth(date: "#{prefix} 1959 and 1965")

        expect(info.year_range_from).to eq(1959)
        expect(info.year_range_to).to eq(1965)
      end
    end

    # A full-date span crossing years carries days the year bounds
    # cannot hold and names no single birth year, so it publishes
    # nothing rather than a coarsened or invented claim.
    it 'does not reduce a full-date span to a year span' do
      info = birth(date: '28 Feb 1962 to 28 Feb 1963')

      expect(info.year_range_from).to be_nil
      expect(info.year_range_to).to be_nil
      expect(info.date).to be_nil
      expect(info.year).to be_nil
    end

    # ...but when both endpoints state the SAME year, that year is
    # asserted outright, twice, and the whole interval lies inside it.
    # Publishing nothing there would discard a certainly-true fact to
    # avoid a false one that is not on offer.
    it 'retains the exact year from a same-year full-date span' do
      info = birth(date: '01 Jan 1962 to 31 Dec 1962')

      expect(info.year).to eq(1962)
      expect(info.date).to be_nil
      expect(info.year_range_from).to be_nil
      expect(info.year_range_to).to be_nil
    end

    # Not special-cased to whole-calendar-year endpoints — what matters
    # is that both endpoints name the same year, not which days they are.
    it 'retains the year from a partial same-year span' do
      info = birth(date: '28 Feb 1962 to 07 Dec 1962')

      expect(info.year).to eq(1962)
      expect(info.date).to be_nil
    end

    # A qualified span is a grammar nobody designed. It stays silent
    # rather than being folded into the strict same-year rule.
    it 'stays silent on a qualified same-year span' do
      info = birth(date: 'circa 01 Jan 1962 to 31 Dec 1962')

      expect(info.year).to be_nil
      expect(info.date).to be_nil
      expect(info.year_range_from).to be_nil
      expect(info.year_range_to).to be_nil
    end

    it 'does not reduce a month span either' do
      info = birth(date: 'Mar 1980 to Mar 1981')

      expect(info.year_range_from).to be_nil
      expect(info.date).to be_nil
      expect(info.year).to be_nil
    end

    # Recognising a span and publishing one are separate. An abbreviated
    # span matches no anchored pattern, so it yields no bounds — but it
    # must not yield the 1 January date Date._parse reads out of its
    # opening half either.
    it 'publishes nothing at all for an abbreviated span' do
      info = birth(date: '01 Jan 1973 to 31 Dec')

      expect(info.date).to be_nil
      expect(info.year).to be_nil
      expect(info.year_range_from).to be_nil
      expect(info.year_range_to).to be_nil
    end
  end

  # Rejected, not reordered: reordering would publish a span the source
  # never stated. It raises rather than returning nil so that "names no
  # span" and "names a span that cannot be true" stay distinguishable.
  describe 'a reversed closed range' do
    it 'is rejected when stated as text' do
      expect { transformer.send(:create_birth_info, date: '1964 to 1962') }
        .to raise_error(Ammitto::Transformers::InvalidYearRangeError,
                        /1964 > 1962/)
    end

    it 'is rejected when stated as bounds' do
      expect do
        transformer.send(:create_birth_info,
                         year_range_from: 1965, year_range_to: 1959)
      end.to raise_error(Ammitto::Transformers::InvalidYearRangeError)
    end

    it 'accepts a span whose bounds are equal' do
      info = transformer.send(:create_birth_info,
                              year_range_from: 1962, year_range_to: 1962)

      expect(info.year_range_from).to eq(1962)
      expect(info.year_range_to).to eq(1962)
    end

    # An open bound has nothing to be out of order with.
    it 'never rejects an open bound' do
      expect { transformer.send(:create_birth_info, year_range_to: 1958) }
        .not_to raise_error
    end
  end

  # Presence is decided before normalization. Deciding it after would
  # turn a stated-but-unusable bound into "no bound stated", which hands
  # authority back to the date string: the record would then publish a
  # span read out of its text while the bounds the source actually
  # stated were dropped without a word.
  describe 'a stated bound that is not a year' do
    it 'is rejected rather than falling back to the date string' do
      expect do
        transformer.send(:create_birth_info, date: '1962 to 1964',
                                             year_range_from: 'unknown')
      end.to raise_error(Ammitto::Transformers::InvalidYearRangeError,
                         /not a year/)
    end

    it 'is rejected on the upper bound too' do
      expect do
        transformer.send(:create_birth_info, year_range_to: 'n/a')
      end.to raise_error(Ammitto::Transformers::InvalidYearRangeError)
    end

    it 'is rejected when the bound is a non-positive number' do
      expect do
        transformer.send(:create_birth_info, year_range_from: 0)
      end.to raise_error(Ammitto::Transformers::InvalidYearRangeError)
    end

    # Absent is not malformed: no bound at all still lets the date
    # string speak.
    it 'still reads the date string when no bound is stated at all' do
      info = transformer.send(:create_birth_info, date: '1962 to 1964')

      expect(info.year_range_from).to eq(1962)
    end
  end

  describe '#extract_year_range' do
    it 'accepts only a value that is wholly a year span' do
      expect(transformer.send(:extract_year_range, '1962 to 1964'))
        .to eq([1962, 1964])
      expect(transformer.send(:extract_year_range, 'Between 1959 and 1965'))
        .to eq([1959, 1965])
    end

    # Two years in a string is not enough. These carry finer precision,
    # or no span at all, and reading them as year spans would either
    # discard stated days or invent a span outright.
    it 'refuses strings that merely contain two years' do
      ['28 Feb 1962 to 28 Feb 1963', 'Mar 1980 to Mar 1981',
       '01 Jan 1973 to 31 Dec 1973', 'born 1962, naturalised 1964',
       'passport issued 1962 to 1964', '1962 to 1964 (unconfirmed)',
       '19621964'].each do |value|
        expect(transformer.send(:extract_year_range, value))
          .to(be_nil, "expected #{value.inspect} not to be read as a year span")
      end
    end

    # No corpus states a span this way — 0 of 5795 distinct OFAC
    # dateOfBirth values, none in the DFAT corpus, and the EU uses XML
    # attributes — so it is an unsupported input, not a misread one.
    it 'does not recognise the hyphen spelling, in either dash' do
      expect(transformer.send(:extract_year_range, '1962-1964')).to be_nil
      expect(transformer.send(:extract_year_range, '1962–1964')).to be_nil
    end

    it 'ignores non-strings' do
      expect(transformer.send(:extract_year_range, nil)).to be_nil
      expect(transformer.send(:extract_year_range, Date.new(1970, 1, 1)))
        .to be_nil
    end
  end

  # Broader than #multiple_years? on purpose: "01 Jan 1973 to 31 Dec
  # 1973" names one distinct year twice, so a uniqueness test cannot see
  # the span in it, yet Date._parse happily returns its 1 January
  # opening endpoint as though the source had stated that date.
  describe '#date_span?' do
    it 'is true for every span spelling the corpora use' do
      ['1962 to 1964', '28 Feb 1962 to 28 Feb 1963',
       '01 Jan 1973 to 31 Dec 1973', 'Mar 1980 to Mar 1981',
       'Between 1959 and 1965',
       'Approximately: Between 1959 and 1965'].each do |value|
        expect(transformer.send(:date_span?, value))
          .to(be(true), "expected #{value.inspect} to read as a span")
      end
    end

    it 'is false for a single point in time, however written' do
      ['03 Oct 1988', '1975', 'circa 1960', 'Oct 1988', '00/00/1963',
       '19620101', '1963 (1963)', 'Toronto 1963'].each do |value|
        expect(transformer.send(:date_span?, value))
          .to(be(false), "expected #{value.inspect} not to read as a span")
      end
    end

    it 'needs a year before the connector' do
      expect(transformer.send(:date_span?, 'Jan and Feb 1970')).to be false
    end

    # Every connector is tried, not only the first, so a value whose
    # opening connector is not the span connector still reads correctly.
    it 'finds the span even when an earlier connector is not the span' do
      expect(transformer.send(:date_span?, 'Jan and Feb 1970 to 1972'))
        .to be true
    end

    # No corpus states an abbreviated span, so no bounds are extracted
    # from one. It is still recognised as a span, because the question
    # this predicate answers is "is this NOT one complete date" — and
    # Date._parse would otherwise read its opening half and publish
    # 1 January 1973 as a stated birth date.
    it 'recognises a span whose second half omits the year' do
      expect(transformer.send(:date_span?, '01 Jan 1973 to 31 Dec')).to be true
    end

    it 'needs a year in the first half, not merely digits' do
      expect(transformer.send(:date_span?, 'Jan 5 and Feb 1970')).to be false
    end
  end

  describe '#parse_complete_date' do
    it 'parses a complete ISO date' do
      expect(transformer.send(:parse_complete_date, '1957-05-05'))
        .to eq(Date.new(1957, 5, 5))
    end

    it 'returns nil for a bare year' do
      expect(transformer.send(:parse_complete_date, '1975')).to be_nil
    end

    it 'returns nil for a zero-padded partial date' do
      expect(transformer.send(:parse_complete_date, '1963-00-00')).to be_nil
    end

    it 'returns nil for a month-year string' do
      expect(transformer.send(:parse_complete_date, 'Oct 1988')).to be_nil
    end

    it 'returns nil for an impossible date' do
      expect(transformer.send(:parse_complete_date, '31/02/1990')).to be_nil
    end

    # Date._parse reads only the opening half of a span and returns it
    # as a complete date. "01 Jan 1973 to 31 Dec 1973" is OFAC's way of
    # saying "some day in 1973"; reading it as 1 January invented the
    # very January date this gem stopped asserting elsewhere.
    it 'returns nil for a span rather than its opening endpoint' do
      ['28 Feb 1962 to 28 Feb 1963', '01 Jan 1973 to 31 Dec 1973',
       '26 Sep 1946 to 07 Dec 1946'].each do |value|
        expect(transformer.send(:parse_complete_date, value))
          .to(be_nil, "expected #{value.inspect} to yield no single date")
      end
    end

    it 'still parses an ordinary complete date unchanged' do
      expect(transformer.send(:parse_complete_date, '28 Feb 1962'))
        .to eq(Date.new(1962, 2, 28))
    end
  end

  describe '#extract_birth_year' do
    it 'extracts a bare year' do
      expect(transformer.send(:extract_birth_year, '1975')).to eq(1975)
    end

    it 'extracts the year from a circa expression' do
      expect(transformer.send(:extract_birth_year, 'circa 1960')).to eq(1960)
    end

    it 'extracts the year from a zeroed partial date' do
      expect(transformer.send(:extract_birth_year, '00/00/1963')).to eq(1963)
    end

    it 'yields nil for a year range — a span names no single year' do
      expect(transformer.send(:extract_birth_year, '1962 to 1964')).to be_nil
    end

    it 'yields nil for every spelling of a year range' do
      ['1962 to 1964', 'between 1962 and 1964', '1962-1964',
       '1962–1964', 'circa 1962 to 1964'].each do |range|
        expect(transformer.send(:extract_birth_year, range))
          .to(be_nil, "expected #{range.inspect} to name no single year")
      end
    end

    # The uniqueness test cannot see this one: it names 1973 twice. The
    # year is nevertheless not a stated year but the endpoint of a span.
    it 'yields nil for a span that repeats one year' do
      expect(transformer.send(:extract_birth_year, '01 Jan 1973 to 31 Dec 1973'))
        .to be_nil
    end

    it 'yields nil for non-strings' do
      expect(transformer.send(:extract_birth_year, nil)).to be_nil
      expect(transformer.send(:extract_birth_year, Date.new(1970, 1, 1))).to be_nil
    end
  end

  describe '#multiple_years?' do
    it 'is true only when two different years are named' do
      expect(transformer.send(:multiple_years?, '1962 to 1964')).to be true
      expect(transformer.send(:multiple_years?, '1962-1964')).to be true
      expect(transformer.send(:multiple_years?, 'between 1962 and 1964'))
        .to be true
    end

    it 'is false for one year, however it is written' do
      ['1975', '00/00/1963', '03 Oct 1988', '1963 (1963)']
        .each do |str|
          expect(transformer.send(:multiple_years?, str))
            .to(be(false), "expected #{str.inspect} to name one year")
        end
    end

    # A guard reading "19620101" as 1962 and 0101 would reject a date
    # the parser handles today.
    it 'does not split a run of digits into two years' do
      expect(transformer.send(:multiple_years?, '19620101')).to be false
    end
  end

  describe '#circa_string?' do
    it 'recognizes circa markers' do
      expect(transformer.send(:circa_string?, 'circa 1960')).to be true
      expect(transformer.send(:circa_string?, 'c. 1955')).to be true
      expect(transformer.send(:circa_string?, 'approximately 1965')).to be true
    end

    it 'recognizes the bare "c" marker extract_birth_year strips' do
      expect(transformer.send(:circa_string?, 'c 1955')).to be true
      expect(transformer.send(:circa_string?, 'C 1955')).to be true
    end

    # The year and the circa flag are read from the same string by two
    # different methods; when they disagree the entity claims an exact
    # birth year the source only approximated.
    it 'agrees with extract_birth_year on both "c" spellings' do
      ['c 1955', 'c. 1955'].each do |str|
        expect(transformer.send(:extract_birth_year, str)).to eq(1955)
        expect(transformer.send(:circa_string?, str)).to be true
      end
    end

    it 'rejects plain dates and non-strings' do
      expect(transformer.send(:circa_string?, '03 Oct 1988')).to be false
      expect(transformer.send(:circa_string?, nil)).to be false
    end

    it 'does not read a word starting with c as a circa marker' do
      expect(transformer.send(:circa_string?, 'China 1955')).to be false
      expect(transformer.send(:circa_string?, 'c1955')).to be false
    end
  end
end
