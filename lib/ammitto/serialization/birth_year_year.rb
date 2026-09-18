# frozen_string_literal: true

require_relative 'birth_year_value'

module Ammitto
  module Serialization
    module BirthYear
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
    end
  end
end
