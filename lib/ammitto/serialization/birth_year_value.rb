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
    end
  end
end
