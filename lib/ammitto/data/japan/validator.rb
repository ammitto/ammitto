# frozen_string_literal: true

require 'yaml'
require 'json'
begin
  require 'json-schema'
rescue LoadError
  # json-schema not available - validation will be skipped
end

require_relative 'schema_loader'
require_relative 'schema_resolver'

module Ammitto
  module Data
    module Japan
      # Validates Japan source YAML files against JSON schemas
      #
      # Validator provides comprehensive validation of Japan sanctions data files
      # against JSON schemas. It supports multiple schema types and provides
      # detailed error reporting.
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
          @schemas_dir = schemas_dir || default_schemas_dir
          @errors = []
          @schema_cache = {}
        end

        # Validate a single YAML file
        #
        # @param file_path [String] Path to YAML file
        # @return [Boolean] true if valid
        def validate(file_path)
          @errors = []

          unless File.exist?(file_path)
            @errors << { path: file_path, message: 'File not found' }
            return false
          end

          data = load_yaml(file_path)
          return false if data.nil?

          schema_type = SchemaResolver.resolve(file_path, data)
          schema = load_schema(schema_type)
          return false if schema.nil?

          validate_against_schema(data, schema, file_path)
        end

        # Validate multiple files
        #
        # @param file_paths [Array<String>] List of file paths to validate
        # @return [Hash] Validation report with :valid, :total_files, :valid_files,
        #   :invalid_files, :errors
        def validate_files(file_paths)
          report = {
            valid: true,
            total_files: 0,
            valid_files: 0,
            invalid_files: 0,
            errors: []
          }

          file_paths.each do |file|
            report[:total_files] += 1
            if validate(file)
              report[:valid_files] += 1
            else
              report[:valid] = false
              report[:invalid_files] += 1
              report[:errors] << { file: file, errors: @errors.dup }
            end
          end

          report
        end

        # Validate all files in sources directory
        #
        # @param sources_dir [String, nil] Path to sources directory
        # @return [Hash] Validation report
        def validate_all(sources_dir = nil)
          sources_dir ||= File.join(File.dirname(@schemas_dir), 'sources')

          unless Dir.exist?(sources_dir)
            return {
              valid: false,
              total_files: 0,
              valid_files: 0,
              invalid_files: 0,
              errors: [{ message: "Sources directory not found: #{sources_dir}" }]
            }
          end

          yaml_files = find_yaml_files(sources_dir)
          validate_files(yaml_files)
        end

        # Get list of YAML files in directory
        #
        # @param sources_dir [String] Path to sources directory
        # @return [Array<String>] List of YAML file paths
        def find_yaml_files(sources_dir)
          Dir.glob(File.join(sources_dir, '**', '*.yml')) +
            Dir.glob(File.join(sources_dir, '**', '*.yaml'))
        end

        private

        # Default schemas directory (ammitto/schemas/japan)
        def default_schemas_dir
          File.expand_path('../../../schemas/japan', __dir__)
        end

        # Load a YAML file with error handling
        # @param file_path [String] Path to YAML file
        # @return [Hash, nil] Parsed content or nil on error
        def load_yaml(file_path)
          YAML.safe_load_file(file_path, permitted_classes: [Date, Time], aliases: true)
        rescue Psych::SyntaxError => e
          @errors << { path: file_path, message: "YAML syntax error: #{e.message}" }
          nil
        rescue StandardError => e
          @errors << { path: file_path, message: "Failed to load file: #{e.message}" }
          nil
        end

        # Load a schema by type
        # @param schema_type [Symbol] The schema type
        # @return [Hash, nil] The schema or nil if not found
        def load_schema(schema_type)
          @schema_cache[schema_type] ||= begin
            SchemaLoader.load(schema_type)
          rescue SchemaNotFoundError => e
            @errors << { message: e.message }
            nil
          end
        end

        # Validate data against a JSON schema
        # @param data [Hash] The data to validate
        # @param schema [Hash] The JSON schema
        # @param file_path [String] The file path for error reporting
        # @return [Boolean] true if valid
        def validate_against_schema(data, schema, file_path)
          unless defined?(JSON::Validator)
            @errors << { path: file_path, message: 'json-schema gem not available for validation' }
            return false
          end

          begin
            # Convert to JSON and back to ensure proper format for validator
            json_content = JSON.parse(data.to_json)
            JSON::Validator.validate!(schema, json_content, validate_schema: false)
            true
          rescue JSON::Schema::ValidationError => e
            @errors << { path: file_path, message: e.message }
            false
          rescue JSON::Schema::SchemaError => e
            @errors << { path: file_path, message: "Schema error: #{e.message}" }
            false
          rescue StandardError => e
            @errors << { path: file_path, message: "Validation error: #{e.message}" }
            false
          end
        end
      end
    end
  end
end
