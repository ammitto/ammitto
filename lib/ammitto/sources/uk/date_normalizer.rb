# frozen_string_literal: true

module Ammitto
  module Sources
    module Uk
      # Utility module for normalizing UK date formats
      #
      # UK sanctions data uses DD/MM/YYYY format, but we want ISO 8601 (YYYY-MM-DD).
      # Include this module to get normalization methods.
      #
      # @example
      #   class MyModel
      #     include DateNormalizer
      #
      #     attribute :some_date, :string
      #
      #     def some_date
      #       normalize_date(@some_date)
      #     end
      #   end
      #
      module DateNormalizer
        # Normalize a date string from DD/MM/YYYY to YYYY-MM-DD
        #
        # @param date_string [String, nil] Date in DD/MM/YYYY or other format
        # @return [String, nil] Date in YYYY-MM-DD format, or nil if invalid
        #
        # @example
        #   normalize_date("29/06/2012")  # => "2012-06-29"
        #   normalize_date("12/01/2022")  # => "2022-01-12"
        #   normalize_date("2012-06-29")  # => "2012-06-29" (already normalized)
        #   normalize_date(nil)           # => nil
        #   normalize_date("")            # => nil
        #
        def normalize_date(date_string)
          return nil if date_string.nil? || date_string.strip.empty?
          return date_string if iso_format?(date_string)

          parse_uk_format(date_string) || date_string
        end

        private

        # Check if date is already in ISO format (YYYY-MM-DD)
        def iso_format?(date_string)
          date_string =~ /^\d{4}-\d{2}-\d{2}$/
        end

        # Parse UK date format (DD/MM/YYYY) and convert to ISO
        def parse_uk_format(date_string)
          match = date_string.match(%r{^(\d{1,2})/(\d{1,2})/(\d{4})$})
          return nil unless match

          day = match[1].to_i.to_s.rjust(2, '0')
          month = match[2].to_i.to_s.rjust(2, '0')
          year = match[3]
          "#{year}-#{month}-#{day}"
        end

        # Normalize an array of date strings
        #
        # @param dates [Array<String>, nil] Array of date strings
        # @return [Array<String>] Array of normalized dates
        #
        def normalize_dates(dates)
          return [] if dates.nil?

          dates.map { |d| normalize_date(d) }.compact
        end
      end
    end
  end
end
