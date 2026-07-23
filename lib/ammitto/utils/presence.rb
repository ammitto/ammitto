# frozen_string_literal: true

module Ammitto
  module Utils
    # Presence predicates for the ontology layer, as explicit module
    # functions — no core-class patching, so nothing leaks into consumers'
    # runtimes. Semantics match ActiveSupport: nil, false, empty
    # collections, and whitespace-only strings (Unicode included) are blank.
    module Presence
      module_function

      # @param value [Object]
      # @return [Boolean] true when the value is nil, false, empty, or
      #   whitespace-only
      def blank?(value)
        case value
        when nil, false
          true
        when String
          value.match?(/\A[[:space:]]*\z/)
        else
          value.respond_to?(:empty?) ? !!value.empty? : false
        end
      end

      # @param value [Object]
      # @return [Boolean] inverse of .blank?
      def present?(value)
        !blank?(value)
      end
    end
  end
end
