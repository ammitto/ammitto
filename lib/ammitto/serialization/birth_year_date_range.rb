# frozen_string_literal: true

require_relative 'birth_year_value'

module Ammitto
  module Serialization
    module BirthYear
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
