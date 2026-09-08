# frozen_string_literal: true

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
        # The "Approximately" prefix is captured rather than discarded:
        # it is what makes the span circa, and a span is not approximate
        # by itself. "Between 1959 and 1965" states its bounds exactly.
        YEAR_RANGE = /
          \A(?:(approximately)\s*:?\s*)?
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

        def to_date
          return nil unless year
          return nil if precision == 'year' && !month

          begin
            Date.new(year, month || 1, day || 1)
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
