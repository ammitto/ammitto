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

    # DFAT publishes most of its dates numerically. Every one of these
    # shapes reached the year-only fallback before, so the day and the
    # month the source did state were thrown away.
    it 'parses an ISO date "1983-08-01"' do
      date = described_class.parse('1983-08-01')
      expect(date.year).to eq(1983)
      expect(date.month).to eq(8)
      expect(date.day).to eq(1)
      expect(date.precision).to eq('full')
    end

    # Day-first, not month-first: across the corpus the second component
    # never exceeds 12 while the first reaches 31. Reading this as
    # September, not the 18th month, is the whole point of the example.
    it 'reads a slash date day-first, as DFAT writes it' do
      date = described_class.parse('18/09/1963')
      expect(date.year).to eq(1963)
      expect(date.month).to eq(9)
      expect(date.day).to eq(18)
      expect(date.precision).to eq('full')
    end

    it 'parses an unpadded slash date "6/04/1961"' do
      date = described_class.parse('6/04/1961')
      expect([date.year, date.month, date.day]).to eq([1961, 4, 6])
    end

    it 'parses a numeric month and year "08/1977"' do
      date = described_class.parse('08/1977')
      expect(date.year).to eq(1977)
      expect(date.month).to eq(8)
      expect(date.day).to be_nil
      expect(date.precision).to eq('month')
    end

    # Refused, not clamped. A shape that cannot be a date keeps the
    # behaviour it already had rather than gaining a month DFAT never
    # stated.
    it 'refuses a numeric shape that is not a real date' do
      expect(described_class.parse('31/02/1970').month).to be_nil
      expect(described_class.parse('31/02/1970').precision).to eq('year')
      expect(described_class.parse('1983-13-01').month).to be_nil
      expect(described_class.parse('1983-13-01').precision).to eq('year')
    end

    # The month-year shape has no Date.valid_date? to lean on, so its
    # range check is the only thing between "13/1977" and a record
    # asserting a thirteenth month at month precision. A zero is the same
    # trap the rest of this file already had to close once.
    it 'refuses a month-and-year whose month is not a month' do
      %w[13/1977 00/1977 0/1977 99/1977].each do |value|
        date = described_class.parse(value)
        expect(date.month).to be_nil
        expect(date.year).to eq(1977)
        expect(date.precision).to eq('year')
      end
    end

    # Anchored on purpose. A cell holding two dates states neither as THE
    # birth date, and reading the first one would publish a claim the
    # source did not make.
    it 'leaves a cell holding more than one numeric date to the fallback' do
      date = described_class.parse('19/12/1962 30/12/1965')
      expect(date.month).to be_nil
      expect(date.precision).to eq('year')

      annotated = described_class.parse('a) 30/04/1963 b) 1960')
      expect(annotated.month).to be_nil
      expect(annotated.precision).to eq('year')
    end

    # circa outranks the shape: the marker is the source's own hedge and
    # a precise-looking numeric date does not withdraw it.
    it 'keeps circa precision on a hedged numeric date' do
      date = described_class.parse('circa 1983-08-01')
      expect(date.circa).to be true
      expect(date.precision).to eq('circa')
      expect([date.year, date.month, date.day]).to eq([1983, 8, 1])
    end

    # DFAT's own spelling for a scalar approximate year. The old test was
    # start_with?('circa', 'c.', 'c'), which never listed "approximately",
    # so this exact value published as an exact 1968.
    it 'parses "Approximately 1968" as circa, not exact' do
      date = described_class.parse('Approximately 1968')
      expect(date.year).to eq(1968)
      expect(date.circa).to be true
      expect(date.precision).to eq('circa')
    end

    # A bare "c" needs the same boundary the other spellings do. Without
    # it, the old start_with?('circa', 'c.', 'c') test read "China 1955"
    # as an approximate 1955. CIRCA_MARKER's lookahead stops the match;
    # MARKER_LIKE then declines the value outright rather than let the
    # word/year branch below read "china" as a failed month and publish
    # 1955 anyway.
    it 'does not read a word starting like a marker as one' do
      date = described_class.parse('China 1955')

      expect(date.year).to be_nil
      expect(date.circa).not_to be(true)
      expect(date.precision).to eq('unknown')
    end

    it 'returns nil for empty string' do
      expect(described_class.parse('')).to be_nil
    end

    it 'returns nil for nil' do
      expect(described_class.parse(nil)).to be_nil
    end

    # DFAT publishes ranges in this shape, which is one of the multi-year
    # date-of-birth spellings the corpus carries. The day group used to
    # match the "59" inside 1959, and parse_month returned 0 for "and",
    # so the record asserted day 59 of month 0 at full precision.
    it 'does not read a day out of the middle of a year' do
      date = described_class.parse('Approximately: Between 1959 and 1965')

      expect(date.day).to be_nil
      expect(date.month).to be_nil
      expect(date.precision).to eq('range')
    end

    # The year-only fallback used to seize the first year in the value
    # and publish 1959 as THE birth year. Neither bound is that.
    it 'records both bounds of a span and claims no single year' do
      date = described_class.parse('Approximately: Between 1959 and 1965')

      expect(date.year_range_from).to eq(1959)
      expect(date.year_range_to).to eq(1965)
      expect(date.year).to be_nil
    end

    it 'marks the "Approximately" span circa, which it did not before' do
      expect(described_class.parse('Approximately: Between 1959 and 1965').circa)
        .to be true
    end

    # parse_year_range runs before strip_circa_marker and returns early.
    # Reversing that order would let the marker stripper eat
    # "approximately: " first, leaving "between 1959 and 1965" for
    # YEAR_RANGE, which would still match -- but circa would then come
    # from the scalar branch and never run, since parse_year_range
    # already returned. The span shape stays exactly what it was before
    # this change: precision 'range', both bounds, no scalar year.
    it 'keeps the span shape unchanged by the shared marker grammar' do
      date = described_class.parse('Approximately: Between 1959 and 1965')

      expect(date.precision).to eq('range')
      expect(date.circa).to be true
      expect(date.year_range_from).to eq(1959)
      expect(date.year_range_to).to eq(1965)
      expect(date.year).to be_nil
    end

    # Circa follows the source's own marker. A span is not approximate
    # by itself: "Between 1959 and 1965" states its bounds exactly.
    it 'leaves a span without the marker un-circa' do
      date = described_class.parse('Between 1959 and 1965')

      expect(date.year_range_from).to eq(1959)
      expect(date.year_range_to).to eq(1965)
      expect(date.circa).to be false
      expect(date.precision).to eq('range')
    end

    it 'has no date to offer for a span' do
      expect(described_class.parse('Between 1959 and 1965').to_date).to be_nil
    end

    # A span parse must survive the fetch artifact, which is where these
    # values live between fetch and harmonize.
    it 'round-trips both bounds through YAML' do
      date = described_class.parse('Approximately: Between 1959 and 1965')
      restored = described_class.from_yaml(date.to_yaml)

      expect(restored.year_range_from).to eq(1959)
      expect(restored.year_range_to).to eq(1965)
      expect(restored.circa).to be true
      expect(restored.precision).to eq('range')
      expect(restored.year).to be_nil
    end

    # "Approximately 1958" used to stand in here, before it carried a
    # marker of its own: CIRCA_MARKER now claims it first, so this test
    # keeps a word+year value the marker grammar does not recognise.
    it 'drops a month that did not resolve rather than storing zero' do
      date = described_class.parse('Foo 1958')

      expect(date.month).to be_nil
      expect(date.year).to eq(1958)
      expect(date.precision).to eq('year')
    end

    it 'reports full precision only when the month actually resolved' do
      expect(described_class.parse('5 May 1957').precision).to eq('full')
      expect(described_class.parse('5 Foo 1957').precision).to eq('year')
    end
  end

  describe '#to_date' do
    it 'converts to Date object' do
      date = described_class.parse('5 May 1957')
      expect(date.to_date).to eq(Date.new(1957, 5, 5))
    end

    # The guard used to be `precision == 'year' && !month`, so it caught
    # the one label and missed every other one that also has no month.
    # A circa value keeps precision 'circa' by design, and fell straight
    # through to `month || 1`.
    it 'offers no date when the source stated no month' do
      ['circa 1957', 'c. 1957', 'Approximately 1958', '1957'].each do |value|
        parsed = described_class.parse(value)

        expect(parsed.year).not_to be_nil, "#{value.inspect} lost its year"
        expect(parsed.to_date).to be_nil, "#{value.inspect} asserted a date"
      end
    end

    # A circa span used to miss YEAR_RANGE, fall through to the month/year
    # branch as "between 1960", and publish 1960 as THE birth year with
    # 1 January as the date. The date half was this method's; the year half
    # was still leaking, and both are gone now: the value is a span.
    it 'offers no date for a circa span, and no scalar year either' do
      ['Circa between 1960 and 1962',
       'Circa between 1975 and 1977'].each do |value|
        parsed = described_class.parse(value)

        expect(parsed.to_date).to be_nil
        expect(parsed.year).to be_nil, "#{value.inspect} kept a scalar year"
        expect(parsed.precision).to eq('range')
        expect(parsed.circa).to be true
      end

      parsed = described_class.parse('Circa between 1960 and 1962')
      expect(parsed.year_range_from).to eq(1960)
      expect(parsed.year_range_to).to eq(1962)
    end

    # A glued marker still marks the span. Declining it would not reject
    # the value: #parse falls through to the scalar branch and keeps the
    # first year alone, so the cost of refusing the spelling is a birth
    # year the source never stated. No source writes it glued, which is
    # why only this example carries it.
    it 'reads a glued approximately as the span marker' do
      parsed = described_class.parse('approximatelyBetween 1959 and 1965')

      expect(parsed.precision).to eq('range')
      expect(parsed.circa).to be(true)
      expect(parsed.year).to be_nil
      expect(parsed.year_range_from).to eq(1959)
      expect(parsed.year_range_to).to eq(1965)
    end

    it 'reads a glued circa as the span marker' do
      parsed = described_class.parse('circaBetween 1960 and 1962')

      expect(parsed.precision).to eq('range')
      expect(parsed.circa).to be(true)
      expect(parsed.year).to be_nil
      expect(parsed.year_range_from).to eq(1960)
      expect(parsed.year_range_to).to eq(1962)
    end

    # 0 is #parse_month's sentinel for a word that is not a month, so an
    # instance carrying it has no month at all. #parse clears it, but an
    # instance deserialized from an older fetch artifact can still hold one,
    # and the guard should answer that outright rather than let Date.new
    # raise into a rescue.
    # The same rule one argument along. `day || 1` yields 0 for a zero day,
    # because 0 is truthy, so Date.new raises and the rescue returns nil.
    # Right answer, wrong route. These pin the answer AND assert it is not
    # reached by exception, by covering the parse that produces day 0 and
    # the deserialized shape that carries it.
    it 'treats a day of zero as no date rather than the first of the month' do
      expect(described_class.parse('0 May 1957').day).to eq(0)
      expect(described_class.parse('0 May 1957').to_date).to be_nil
      expect(described_class.new(year: 1957, month: 5, day: 0).to_date).to be_nil
      restored = described_class.from_yaml(
        "---\nyear: 1957\nmonth: 5\nday: 0\nprecision: full\n"
      )
      expect(restored.to_date).to be_nil
    end

    # Asserting the ROUTE, not just the answer. Without the guard the answer
    # is still nil, because Date.new(1957, 5, 0) raises and the rescue
    # swallows it, so an outcome-only example passes either way and pins
    # nothing. This one fails the moment the guard is removed.
    it 'answers a zero day without reaching Date.new at all' do
      allow(Date).to receive(:new).and_call_original

      expect(described_class.new(year: 1957, month: 5, day: 0).to_date).to be_nil
      expect(Date).not_to have_received(:new)
    end

    it 'still maps an absent day to the first of its month' do
      expect(described_class.new(year: 1957, month: 5).to_date)
        .to eq(Date.new(1957, 5, 1))
    end

    it 'treats a month of zero as no month' do
      expect(described_class.new(year: 1957, month: 0).to_date).to be_nil
      expect(described_class.new(year: 1957, month: 0, day: 5).to_date)
        .to be_nil
      restored = described_class.from_yaml(
        "---\nyear: 1957\nmonth: 0\nprecision: full\n"
      )
      expect(restored.to_date).to be_nil
    end

    # A month-precision value keeps mapping to the first of its month.
    # That default is unchanged, and stating so pins the scope of this
    # fix: the missing month is the disqualifier, the missing day is not.
    it 'still defaults the day of a month-precision value' do
      expect(described_class.parse('May 1957').to_date)
        .to eq(Date.new(1957, 5, 1))
    end
  end

  # This is the point of the change, not a side effect of it: the AU
  # parser used to read its own start_with?('circa', 'c.', 'c') list
  # while Transformers::BaseTransformer read a differently-shaped
  # CIRCA_MARKER, and the two disagreed on "approximately" -- FlexibleDate
  # missed it entirely. Pinning both constants to the SAME object, rather
  # than to two regexes that happen to match the same strings today,
  # is what stops that gap reopening the next time either grammar grows
  # a spelling.
  describe 'the shared marker grammar' do
    it 'reads CIRCA_MARKER from the one module both layers include' do
      expect(described_class::CIRCA_MARKER)
        .to equal(Ammitto::Utils::CircaMarker::CIRCA_MARKER)
      expect(described_class::CIRCA_MARKER)
        .to equal(Ammitto::Transformers::BaseTransformer::CIRCA_MARKER)
    end

    it 'reads MARKER_LIKE from the one module both layers include' do
      expect(described_class::MARKER_LIKE)
        .to equal(Ammitto::Utils::CircaMarker::MARKER_LIKE)
      expect(described_class::MARKER_LIKE)
        .to equal(Ammitto::Transformers::BaseTransformer::MARKER_LIKE)
    end
  end
end
