# frozen_string_literal: true

module Ammitto
  module Validation
    # Unified result value object for all validation planes
    #
    # Wraps the outcome of a validation run in a single shape regardless
    # of which validator produced it. Errors may be plain strings (as
    # emitted by Schema::Validator) or hashes such as
    # <tt>{ path:, message: }</tt> (as emitted by the file schema
    # validators). Validator-specific extras such as file counts live in
    # {#details}.
    #
    # @example Checking a result
    #   result = Ammitto::Validation.object(data, type: :entity)
    #   result.valid?         # => false
    #   result.error_messages # => ["Missing required field: names"]
    #
    class Result
      # @return [Array<String, Hash>] validation errors
      attr_reader :errors

      # @return [Array<String, Hash>] non-fatal findings
      attr_reader :warnings

      # @return [Hash] validator-specific extras (e.g. file counts)
      attr_reader :details

      # Initialize a result
      #
      # Accepted structures are deep-copied and frozen so a Result
      # cannot be mutated afterwards, through nested error hashes or
      # details arrays included.
      #
      # @param errors [Array<String, Hash>] validation errors
      # @param warnings [Array<String, Hash>] non-fatal findings
      # @param details [Hash] validator-specific extras
      def initialize(errors: [], warnings: [], details: {})
        @errors = deep_freeze(errors)
        @warnings = deep_freeze(warnings)
        @details = deep_freeze(details)
      end

      # Build a passing result
      #
      # @param warnings [Array<String, Hash>] non-fatal findings
      # @param details [Hash] validator-specific extras
      # @return [Result]
      def self.success(warnings: [], details: {})
        new(warnings: warnings, details: details)
      end

      # Build a failing result
      #
      # @param errors [Array<String, Hash>, String, Hash] one error or a
      #   list of errors
      # @param warnings [Array<String, Hash>] non-fatal findings
      # @param details [Hash] validator-specific extras
      # @return [Result]
      def self.failure(errors, warnings: [], details: {})
        errors = [errors] unless errors.is_a?(Array)
        new(errors: errors, warnings: warnings, details: details)
      end

      # Combine many results into one
      #
      # @param results [Array<Result>] results to combine
      # @return [Result] the folded result (valid when empty)
      def self.combine(results)
        results.reduce(new) { |combined, result| combined.merge(result) }
      end

      # Recursively copy a frozen Result structure back into plain
      # mutable objects, for legacy interfaces that predate the frozen
      # contract
      #
      # @param value [Object] structure to copy
      # @return [Object] an independent mutable copy
      def self.deep_dup(value)
        case value
        when Hash
          value.to_h { |key, item| [key, deep_dup(item)] }
        when Array
          value.map { |item| deep_dup(item) }
        when String
          value.dup
        else
          value
        end
      end

      # @return [Boolean] true when no errors were recorded
      def valid?
        errors.empty?
      end

      # Merge with another result
      #
      # Errors and warnings are concatenated; details are shallow-merged
      # with +other+ winning on key conflicts.
      #
      # @param other [Result] result to merge in
      # @return [Result] a new combined result
      def merge(other)
        self.class.new(
          errors: errors + other.errors,
          warnings: warnings + other.warnings,
          details: details.merge(other.details)
        )
      end

      # Human-readable messages for all errors
      #
      # @return [Array<String>] the message of each error, whether the
      #   error is a plain string or a hash with a :message key
      def error_messages
        errors.map { |error| error.is_a?(Hash) ? error[:message] : error.to_s }
      end

      private

      # Recursively copy-and-freeze plain collections and strings;
      # other values pass through untouched
      #
      # @param value [Object] structure to copy
      # @return [Object] an independent frozen copy
      def deep_freeze(value)
        case value
        when Hash
          value.to_h { |key, item| [key, deep_freeze(item)] }.freeze
        when Array
          value.map { |item| deep_freeze(item) }.freeze
        when String
          value.dup.freeze
        else
          value
        end
      end
    end
  end
end
