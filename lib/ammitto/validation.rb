# frozen_string_literal: true

require_relative 'validation/result'
require_relative 'validation/file_schema_validator'
require_relative 'validation/object_validator'

module Ammitto
  # Facade over the gem's validation machinery
  #
  # Entry point for the two in-process validation planes: YAML files
  # against per-country JSON schemas ({FileSchemaValidator}) and
  # in-memory hashes against harmonized-payload rules
  # ({ObjectValidator}). Every call returns a {Result}. The persisted
  # graph plane (scripts/validate_neo4j_data.rb and friends) is
  # intentionally not wrapped here.
  #
  # @example Validate a source file or directory
  #   Ammitto::Validation.file('sources/', country: :china).valid?
  #
  # @example Validate an in-memory entity hash
  #   Ammitto::Validation.object(data, type: :entity).errors
  #
  module Validation
    class << self
      # Validate a YAML file or directory against country schemas
      #
      # @param path [String] a YAML file path or a directory to walk
      # @param country [Symbol, String] a registered country key
      #   (see FileSchemaValidator::COUNTRIES)
      # @return [Result]
      # @raise [UnknownCountryError] for unregistered countries
      def file(path, country:)
        validator = FileSchemaValidator.new(country: country)
        if File.directory?(path)
          validator.validate_directory(path)
        else
          validator.validate_file(path)
        end
      end

      # Validate an in-memory hash as a harmonized payload type
      #
      # @param data [Hash] the data to validate
      # @param type [Symbol, String] one of
      #   ObjectValidator::TYPE_CHECKS keys
      # @return [Result]
      # @raise [ArgumentError] for unknown validation types
      def object(data, type:)
        ObjectValidator.new.validate(data, type: type)
      end
    end
  end
end
