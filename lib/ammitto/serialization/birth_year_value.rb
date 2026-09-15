# frozen_string_literal: true

require 'json'

module Ammitto
  module Serialization
    # Namespace for typed birth-year values emitted by the search index.
    #
    # Each value renders itself as a JSON object. This keeps the type and
    # circa state beside the value instead of requiring parallel row fields.
    module BirthYear
      # Common immutable behaviour for search-index birth-year values.
      class Value
        YEAR_PATTERN = /\A\d{4}\z/

        attr_reader :circa

        # @param circa [Boolean] whether the source marked the value approximate
        def initialize(circa: false)
          @circa = circa == true
          freeze
        end

        # @return [Boolean] whether the source stated the value exactly
        def exact?
          !circa
        end

        # @return [Hash] JSON-ready representation
        def to_hash
          to_h
        end

        # @return [String] JSON representation
        def to_json(*)
          JSON.generate(to_h, *)
        end

        def ==(other)
          other.instance_of?(self.class) && other.to_h == to_h
        end
        alias eql? ==

        # @return [Integer]
        def hash
          to_h.hash
        end

        private

        # @param value [Integer, String] four-digit year
        # @return [String] normalized year
        def normalized_year(value)
          year = value.to_s
          return year.freeze if YEAR_PATTERN.match?(year)

          raise ArgumentError, "birth year must be four digits: #{value.inspect}"
        end
      end

      # A single source-stated birth year.
      #
      # @example An exact year
      #   BirthYear::Year.new(1984)
      #
      # @example An approximate year
      #   BirthYear::Year.new(1984, circa: true)
      class Year < Value
        attr_reader :value

        # @param value [Integer, String] four-digit year
        # @param circa [Boolean] whether the source marked the year approximate
        def initialize(value, circa: false)
          @value = normalized_year(value)
          super(circa: circa)
        end

        # @return [String]
        def type
          'year'
        end

        # @return [Hash]
        def to_h
          {
            type: type,
            value: value,
            circa: circa
          }
        end
      end

      # A source-stated span of birth years. Either bound may be absent.
      #
      # @example A closed span
      #   BirthYear::DateRange.new(from: 1953, to: 1958)
      #
      # @example An open span
      #   BirthYear::DateRange.new(to: 1980)
      class DateRange < Value
        attr_reader :from, :to

        # @param from [Integer, String, nil] lower bound
        # @param to [Integer, String, nil] upper bound
        # @param circa [Boolean] whether the source marked the span approximate
        def initialize(from: nil, to: nil, circa: false)
          @from = normalized_year(from) if from
          @to = normalized_year(to) if to

          raise ArgumentError, 'birth-year range needs at least one bound' unless @from || @to

          super(circa: circa)
        end

        # @return [String]
        def type
          'date_range'
        end

        # @return [Hash]
        def to_h
          {
            type: type,
            from: from,
            to: to,
            circa: circa
          }
        end
      end
    end
  end
end
