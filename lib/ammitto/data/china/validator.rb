# frozen_string_literal: true

require_relative '../../validation'

module Ammitto
  module Data
    module China
      # Validates China source YAML files against JSON schemas
      #
      # Thin compatibility wrapper over
      # Ammitto::Validation::FileSchemaValidator: the validation flow
      # lives in the country-parameterized facade, while this class
      # keeps the original return shapes (Boolean plus #errors for
      # single files, report hashes for batches) for existing callers.
      #
      # @example Validate a single file
      #   validator = Validator.new
      #   if validator.validate('path/to/file.yml')
      #     puts "Valid!"
      #   else
      #     puts validator.errors
      #   end
      #
      # @example Validate all files in a directory
      #   report = validator.validate_all('sources/')
      #   puts "Valid: #{report[:valid_files]}, Invalid: #{report[:invalid_files]}"
      #
      class Validator
        attr_reader :schemas_dir, :errors

        # Initialize the validator
        # @param schemas_dir [String, nil] Optional custom schemas directory
        def initialize(schemas_dir = nil)
          @facade = Validation::FileSchemaValidator.new(country: :china)
          @schemas_dir = schemas_dir || @facade.schemas_dir
          @errors = []
        end

        # Validate a single YAML file
        #
        # @param file_path [String] Path to YAML file
        # @return [Boolean] true if valid
        # rubocop:disable Naming/PredicateMethod -- legacy public API name
        def validate(file_path)
          result = @facade.validate_file(file_path)
          @errors = Validation::Result.deep_dup(result.errors)
          result.valid?
        end
        # rubocop:enable Naming/PredicateMethod

        # Validate multiple files
        #
        # @param file_paths [Array<String>] List of file paths to validate
        # @return [Hash] Validation report with :valid, :total_files,
        #   :valid_files, :invalid_files, :errors
        def validate_files(file_paths)
          result = @facade.validate_files(file_paths)
          @errors = last_file_errors(file_paths, result)
          Validation::FileSchemaValidator.legacy_report(result)
        end

        # Validate all files in sources directory
        #
        # @param sources_dir [String, nil] Path to sources directory
        # @return [Hash] Validation report
        def validate_all(sources_dir = nil)
          sources_dir ||= File.join(File.dirname(@schemas_dir), 'sources')
          files = @facade.find_yaml_files(sources_dir)
          result = @facade.validate_directory(sources_dir)
          @errors = last_file_errors(files, result)
          Validation::FileSchemaValidator.legacy_report(result)
        end

        # Get list of YAML files in directory
        #
        # @param sources_dir [String] Path to sources directory
        # @return [Array<String>] List of YAML file paths
        def find_yaml_files(sources_dir)
          @facade.find_yaml_files(sources_dir)
        end

        private

        # Legacy #errors semantics: batch calls leave the last file's
        # errors behind (empty when the last file was valid)
        #
        # @param file_paths [Array<String>] the validated files, in order
        # @param result [Ammitto::Validation::Result] the batch result
        # @return [Array<Hash>]
        def last_file_errors(file_paths, result)
          last = file_paths.last
          return [] unless last

          group = result.details[:file_errors]
                        &.find { |entry| entry[:file] == last }
          group ? Validation::Result.deep_dup(group[:errors]) : []
        end
      end
    end
  end
end
