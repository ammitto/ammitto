# frozen_string_literal: true

require 'date'
require 'lutaml/model'

module Ammitto
  module Sources
    module Au
      # The Australian sanctions ontology as a whole, how the denormalized
      # CSV maps onto these objects and what the regimes and effects mean,
      # is in lib/ammitto/sources/au.rb.
      # ISO 8601 date with support for partial/imprecise dates
      class FlexibleDate < Lutaml::Model::Serializable
        # DFAT states a span of birth years in one shape:
        # "Approximately: Between 1959 and 1965", and the same shape
        # without the "Approximately:" prefix. Anchored at both ends, so
        # only a value that is wholly a span is read as one.
        #
        # The marker is captured rather than discarded: it is what makes
        # the span circa, and a span is not approximate by itself.
        # "Between 1959 and 1965" states its bounds exactly.
        #
        # "Circa" is admitted alongside "Approximately" because the two
        # mean the same thing and only one of them was listed. A span this
        # grammar declines does not fail closed: #parse falls through to
        # the month/year branch, which reads "between 1960" and keeps 1960
        # as THE birth year. That is the exact failure the early return
        # below exists to prevent, and it was open for one spelling.
        #
        # The marker carries no separator requirement, for that same
        # reason. Requiring one would have declined
        # "approximatelyBetween 1959 and 1965". The previous
        # implementation read that spelling as a span; both ways were
        # measured before the requirement was dropped.
        #
        # The fall-through is a defect in its own right: real records
        # publish their first year because of it today. It is written up,
        # with a dated count, in
        # .codex-context/finding-au-multi-year-cell-picks-one-2026-09-08.md
        # rather than fixed here, because it changes published output.
        YEAR_RANGE = /
          \A(?:(approximately|circa)\s*:?\s*)?
          between\s+(\d{4})\s+and\s+(\d{4})\z
        /xi

        attribute :raw_value, :string    # Original value from CSV
        attribute :year, :integer
        attribute :month, :integer
        attribute :day, :integer
        attribute :circa, :boolean       # Approximate date
        # Lower and upper bound of a stated span of years. While a span
        # is present year, month and day stay nil: neither bound is the
        # birth year, so storing one would assert a year DFAT did not
        # state. An out-of-order span is rejected at the transformer
        # boundary, where the harmonized contract lives, rather than
        # reordered here.
        attribute :year_range_from, :integer
        attribute :year_range_to, :integer
        # 'full', 'month', 'year', 'range', 'circa', or 'unknown' when the
        # cell held no resolvable date at all. Nothing in the gem branches
        # on this value; it is descriptive metadata carried alongside
        # raw_value.
        attribute :precision, :string

        # DFAT states a great many dates numerically, in shapes no
        # alphabetic-month pattern below can see: ISO 1983-08-01 and
        # day-first 18/09/1963, plus a monthless 08/1977. All three fell
        # through to the year-only fallback, which threw the day and the
        # month away and published a bare year the source had not stated.
        #
        # Day-first is measured, not assumed: across the slash values in
        # the corpus the second component never exceeds 12 while the first
        # reaches 31, so the ordering is DFAT's own. Transformer
        # #parse_control_date reads m/d/y, but that is the control-date
        # column of a different feed and these patterns are deliberately
        # not shared with it.
        ISO_DATE = /\A(\d{4})-(\d{1,2})-(\d{1,2})\z/
        SLASH_DATE = %r{\A(\d{1,2})/(\d{1,2})/(\d{4})\z}
        SLASH_MONTH_YEAR = %r{\A(\d{1,2})/(\d{4})\z}

        def self.parse(date_str)
          return nil if date_str.nil? || date_str.empty?

          flexible = new(raw_value: date_str, precision: 'full')

          # Handle various date formats
          # "5 May 1957", "April 1957", "1957", "circa 1957"

          cleaned = date_str.strip.downcase

          # A span is recognised before anything else and returns at
          # once. The year-only fallback below would otherwise seize the
          # first year in the value and publish 1959 as THE birth year —
          # which is what this parser did — and demote_unresolved_month
          # would then rewrite a yearless span's precision to 'unknown'.
          range = parse_year_range(flexible, cleaned)
          return range if range

          if cleaned.start_with?('circa', 'c.', 'c')
            flexible.circa = true
            flexible.precision = 'circa'
            cleaned = cleaned.sub(/^circa\s*|^c\.\s*|^c\s*/, '')
          end

          # Numeric shapes resolve completely or not at all, so they
          # return here rather than falling into demote_unresolved_month.
          numeric = parse_numeric(flexible, cleaned)
          return numeric if numeric

          # Try full date: "5 May 1957" or "May 5, 1957".
          #
          # The day group is guarded with (?<!\d) so it cannot match inside a
          # four-digit year. Without it, "Approximately: Between 1959 and 1965"
          # matched "59 and 1965" and yielded day 59 of month 0.
          if (match = cleaned.match(/(?<!\d)(\d{1,2})\s+(\w+)\s+(\d{4})/))
            flexible.day = match[1].to_i
            flexible.month = parse_month(match[2])
            flexible.year = match[3].to_i
          elsif (match = cleaned.match(/(\w+)\s+(?<!\d)(\d{1,2}),?\s+(\d{4})/))
            flexible.month = parse_month(match[1])
            flexible.day = match[2].to_i
            flexible.year = match[3].to_i
          elsif (match = cleaned.match(/(\w+)\s+(\d{4})/))
            # Month and year only: "May 1957"
            flexible.month = parse_month(match[1])
            flexible.year = match[2].to_i
            flexible.precision = 'month' unless flexible.circa
            flexible.day = nil
          elsif (match = cleaned.match(/(\d{4})/))
            # Year only: "1957"
            flexible.year = match[1].to_i
            flexible.precision = 'year' unless flexible.circa
          end

          # parse_month yields 0 for a word that is not a month, and every
          # branch above stored that unchecked. A record then asserted month 0
          # at full precision -- a claim the source never made.
          demote_unresolved_month(flexible)

          flexible
        end

        # Reduce a parse that never resolved its month to the precision it
        # actually reached, so no record asserts a month or day the source did
        # not state.
        #
        # Month and day are cleared, and precision becomes:
        #   'circa'   — left as-is, the circa marker already says the date is
        #               approximate and outranks the missing month
        #   'year'    — a year resolved, so the record still carries one
        #   'unknown' — nothing resolved at all, e.g. the cell "5/06/1978,  "
        #               whose second comma-separated element is a lone space
        #
        # 'unknown' is a state callers did not previously see. It is emitted
        # into the serialized YAML.
        #
        # Record a stated span of years, or nil when the value states no
        # span. circa follows the source's own "Approximately" marker
        # and is never inferred from the span itself.
        # @param flexible [FlexibleDate] the parse being filled in
        # @param cleaned [String] the stripped, downcased cell value
        # @return [FlexibleDate, nil] the finished parse, or nil
        def self.parse_year_range(flexible, cleaned)
          match = YEAR_RANGE.match(cleaned)
          return nil unless match

          flexible.circa = !match[1].nil?
          flexible.year_range_from = match[2].to_i
          flexible.year_range_to = match[3].to_i
          flexible.precision = 'range'
          flexible
        end

        # Record a wholly numeric date, or nil when the value is not one.
        #
        # Every pattern is anchored, so a cell holding more than one date
        # ("19/12/1962 30/12/1965") or an annotated one ("a) 30/04/1963 b)
        # 1960") is left to the fallback below rather than half-read: the
        # first date in such a cell is not the record's birth date.
        #
        # A shape that matches but cannot be a real date -- month 13, day
        # 32 -- is refused rather than clamped, and falls through to the
        # year-only fallback, which is what it already did.
        # @param flexible [FlexibleDate] the parse being filled in
        # @param cleaned [String] the stripped, downcased cell value
        # @return [FlexibleDate, nil] the finished parse, or nil
        def self.parse_numeric(flexible, cleaned)
          if (match = ISO_DATE.match(cleaned))
            year, month, day = match.captures.map(&:to_i)
          elsif (match = SLASH_DATE.match(cleaned))
            day, month, year = match.captures.map(&:to_i)
          elsif (match = SLASH_MONTH_YEAR.match(cleaned))
            return nil unless (1..12).cover?(match[1].to_i)

            flexible.month = match[1].to_i
            flexible.year = match[2].to_i
            flexible.precision = 'month' unless flexible.circa
            return flexible
          else
            return nil
          end

          return nil unless Date.valid_date?(year, month, day)

          flexible.year = year
          flexible.month = month
          flexible.day = day
          # circa outranks the shape: "circa 1983-08-01" is still a hedge,
          # and the marker is the source's own.
          flexible.precision = 'full' unless flexible.circa
          flexible
        end

        # @param flexible [FlexibleDate] the parse being finalised
        # @return [void]
        def self.demote_unresolved_month(flexible)
          return unless flexible.month.nil? || flexible.month.to_i.zero?

          flexible.month = nil
          flexible.day = nil
          return if flexible.circa

          flexible.precision = flexible.year ? 'year' : 'unknown'
        end

        def self.parse_month(month_str)
          months = %w[january february march april may june july august september october november december]
          idx = months.index(month_str.downcase)
          idx ? idx + 1 : 0
        end

        # Convert to a Date, or return nil when the parse never resolved one.
        #
        # A missing month is the disqualifier, not the precision label. The
        # earlier guard read `precision == 'year' && !month`, which let
        # every other label through with `month || 1` behind it: "circa
        # 1957" keeps precision 'circa' because the circa marker outranks
        # the missing month in #demote_unresolved_month, so it fell through
        # and returned 1 January 1957 -- a day and a month DFAT never
        # stated, on a value whose own label says it is approximate.
        # "Circa between 1960 and 1962" landed there too, though by a
        # different route than it looks: not the year-only fallback but the
        # month/year branch, which reads "between 1960", and parse_month
        # returns 0 for "between" so demote_unresolved_month clears the
        # month while leaving precision 'circa'. YEAR_RANGE admits that
        # spelling now, so the value is a span and never reaches here.
        #
        # A day is still defaulted. A month-precision value legitimately
        # maps to the first of its month, and the AU transformer requires
        # day, month and year itself before it uses this at all
        # (#complete_date_of), so the harmonized output was never exposed
        # to either default.
        #
        # `month.to_i.positive?` rather than a presence check, because 0 is
        # this parser's own sentinel for "the word was not a month"
        # (#parse_month), and #demote_unresolved_month tests for exactly
        # that. #parse clears it, so a 0 arrives only on an instance built
        # directly or deserialized from an older artifact -- and it already
        # returned nil, by raising Date::Error into the rescue below.
        # Asking the question outright says what the guard means and stops
        # a known-invalid value being handled as an exception.
        #
        # The DAY guard is the same rule one argument along, and it is not
        # redundant with `day || 1`. 0 is truthy in Ruby, so `day || 1`
        # yields 0 for a zero day, `Date.new(year, month, 0)` raises, and
        # the rescue below turns that into nil. Right answer, wrong route:
        # this method would be correct only by exception, which is what the
        # month guard above exists to stop. `"0 May 1957"` parses to day 0
        # and reaches it, and so does an instance deserialized with `day: 0`.
        #
        # Zero means the day was READ and is not a day, which is different
        # from absent. Absent is `day || 1`, a month-precision value landing
        # on the first of its month, which the source does support. Corrupt
        # is not, so it stays nil rather than being rounded into a date the
        # source never stated.
        #
        # Worth knowing before editing this: it is `month || 1` that
        # invented 1 January, not the missing guard. Deleting the guard line
        # leaves every example green, because `month.to_i` turns a missing
        # month into 0 and `Date.new(year, 0, 1)` raises Date::Error into the
        # rescue. The guard is here to state the rule, so the method does not
        # depend on an exception to be correct.
        def to_date
          return nil unless year && month.to_i.positive?
          return nil if day && !day.to_i.positive?

          begin
            Date.new(year, month.to_i, day || 1)
          rescue StandardError
            nil
          end
        end

        def to_s
          raw_value
        end
      end
    end
  end
end
