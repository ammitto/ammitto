# frozen_string_literal: true

require_relative 'result'
require_relative '../schema/validator'

module Ammitto
  module Validation
    # In-memory object validator returning unified {Result} objects
    #
    # Wraps Schema::Validator, mapping each of its check methods to a
    # validation type so callers use one entry point for every
    # harmonized-payload shape.
    #
    # @example Validating an entity hash
    #   result = ObjectValidator.new.validate(data, type: :entity)
    #   result.valid? # => true
    #
    class ObjectValidator
      # Validation type to Schema::Validator check method mapping
      TYPE_CHECKS = {
        entity: :validate_entity,
        sanction_entry: :validate_sanction_entry,
        name_variant: :validate_name_variant,
        json_ld: :validate_json_ld
      }.freeze

      # Initialize the validator
      #
      # @param schema_validator [Schema::Validator, nil] override for
      #   testing; defaults to a fresh Schema::Validator
      def initialize(schema_validator: nil)
        @schema_validator = schema_validator || Schema::Validator.new
      end

      # Validate a data hash as the given type
      #
      # @param data [Hash] the data to validate
      # @param type [Symbol, String] one of {TYPE_CHECKS} keys
      # @return [Result]
      # @raise [ArgumentError] for unknown validation types
      def validate(data, type:)
        check = TYPE_CHECKS[type.to_sym] if type.respond_to?(:to_sym)
        unless check
          raise ArgumentError,
                "Unknown validation type: #{type.inspect} " \
                "(supported: #{TYPE_CHECKS.keys.join(', ')})"
        end

        errors = @schema_validator.public_send(check, data)
        Result.new(errors: errors, details: { type: type.to_sym })
      end
    end
  end
end
