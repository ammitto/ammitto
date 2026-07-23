# frozen_string_literal: true

require 'yaml'
require 'json'
begin
  require 'json-schema'
rescue LoadError
  # json-schema not available - validation will be skipped
end

require_relative 'result'
require_relative '../data/china/schema_loader'
require_relative '../data/china/schema_resolver'
require_relative '../data/japan/schema_loader'
require_relative '../data/japan/schema_resolver'

module Ammitto
  module Validation
    # Raised when asked to validate files for an unregistered country
    class UnknownCountryError < ArgumentError; end

    # Country-parameterized YAML-file-vs-JSON-Schema validator
    #
    # Single implementation behind the per-country file validators
    # (Data::China::Validator, Data::Japan::Validator): each country
    # contributes its schema machinery via {COUNTRIES}, and the
    # validation flow (YAML load, schema resolution, JSON-Schema run) is
    # shared. All public methods return {Result} objects.
    #
    # @example Validate a single file
    #   validator = FileSchemaValidator.new(country: :china)
    #   result = validator.validate_file('sources/announcement.yml')
    #   result.valid? # => true
    #
    # @example Validate a directory tree
    #   result = validator.validate_directory('sources/')
    #   result.details[:invalid_files] # => 0
    #
    class FileSchemaValidator
      # Registered per-country schema machinery: the resolver picks a
      # schema type for a file, the loader loads that schema, and
      # schemas_dir is where the country's schema files live.
      COUNTRIES = {
        china: {
          resolver: Data::China::SchemaResolver,
          loader: Data::China::SchemaLoader,
          schemas_dir: Data::China::SchemaLoader::SCHEMAS_DIR
        }.freeze,
        japan: {
          resolver: Data::Japan::SchemaResolver,
          loader: Data::Japan::SchemaLoader,
          schemas_dir: Data::Japan::SchemaLoader::SCHEMAS_DIR
        }.freeze
      }.freeze

      # Errors the country schema loaders raise for unknown or missing
      # schema files
      MISSING_SCHEMA_ERRORS = [
        Data::China::SchemaNotFoundError,
        Data::Japan::SchemaNotFoundError
      ].freeze

      # @return [Symbol] registered country key (:china, :japan)
      attr_reader :country

      # @return [String] directory holding the country's schema files
      attr_reader :schemas_dir

      # Initialize a validator for one country
      #
      # @param country [Symbol, String] a {COUNTRIES} key
      # @raise [UnknownCountryError] for unregistered countries
      def initialize(country:)
        entry = COUNTRIES[country&.to_sym]
        unless entry
          raise UnknownCountryError,
                "Unknown country: #{country.inspect} " \
                "(supported: #{COUNTRIES.keys.join(', ')})"
        end

        @country = country.to_sym
        @resolver = entry[:resolver]
        @loader = entry[:loader]
        @schemas_dir = entry[:schemas_dir]
        @schema_cache = {}
      end

      # Validate a single YAML file against its resolved schema
      #
      # @param file_path [String] path to the YAML file
      # @return [Result]
      def validate_file(file_path)
        Result.new(errors: file_errors(file_path),
                   details: { file: file_path })
      end

      # Validate multiple YAML files
      #
      # @param file_paths [Array<String>] paths to validate
      # @return [Result] with :total_files, :valid_files, :invalid_files
      #   counts, per-file :file_errors groups, and the validated
      #   :files list (in validation order) in {Result#details}
      def validate_files(file_paths)
        groups = file_paths.filter_map do |file|
          errors = file_errors(file)
          { file: file, errors: errors } if errors.any?
        end

        Result.new(
          errors: groups.flat_map { |group| group[:errors] },
          details: {
            total_files: file_paths.length,
            valid_files: file_paths.length - groups.length,
            invalid_files: groups.length,
            file_errors: groups,
            files: file_paths
          }
        )
      end

      # Validate every YAML file under a directory
      #
      # @param sources_dir [String] directory to walk
      # @return [Result]
      def validate_directory(sources_dir)
        unless Dir.exist?(sources_dir)
          return Result.failure(
            { message: "Sources directory not found: #{sources_dir}" },
            details: { total_files: 0, valid_files: 0, invalid_files: 0,
                       file_errors: [], files: [] }
          )
        end

        validate_files(find_yaml_files(sources_dir))
      end

      # List YAML files under a directory
      #
      # @param sources_dir [String] directory to walk
      # @return [Array<String>] .yml and .yaml file paths
      def find_yaml_files(sources_dir)
        Dir.glob(File.join(sources_dir, '**', '*.yml')) +
          Dir.glob(File.join(sources_dir, '**', '*.yaml'))
      end

      # Render a multi-file {Result} in the legacy report shape returned
      # by the per-country validators
      #
      # @param result [Result] produced by {#validate_files} or
      #   {#validate_directory}
      # @return [Hash] with :valid, :total_files, :valid_files,
      #   :invalid_files and :errors keys
      def self.legacy_report(result)
        details = result.details
        errors = details.fetch(:file_errors, [])
        errors = result.errors if errors.empty? && !result.valid?

        {
          valid: result.valid?,
          total_files: details.fetch(:total_files, 0),
          valid_files: details.fetch(:valid_files, 0),
          invalid_files: details.fetch(:invalid_files, 0),
          errors: Result.deep_dup(errors)
        }
      end

      private

      # Collect all errors for one file
      #
      # @param file_path [String] path to the YAML file
      # @return [Array<Hash>] empty when the file is valid
      def file_errors(file_path)
        return not_found(file_path) unless File.exist?(file_path)

        errors = []
        data = load_yaml(file_path, errors)
        return errors if data.nil?

        schema = load_schema(@resolver.resolve(file_path, data), errors)
        return errors if schema.nil?

        schema_errors(data, schema, file_path)
      end

      # Parse a YAML file, recording any failure
      #
      # @param file_path [String] path to the YAML file
      # @param errors [Array<Hash>] error sink
      # @return [Object, nil] parsed content, or nil when unusable
      def load_yaml(file_path, errors)
        data = YAML.safe_load_file(file_path,
                                   permitted_classes: [Date, Time],
                                   aliases: true)
        if data.nil?
          errors << { path: file_path, message: 'YAML file is empty' }
          return nil
        end

        data
      rescue Psych::SyntaxError => e
        errors << { path: file_path,
                    message: "YAML syntax error: #{e.message}" }
        nil
      rescue StandardError => e
        errors << { path: file_path,
                    message: "Failed to load file: #{e.message}" }
        nil
      end

      # Error list for a nonexistent file
      #
      # @param file_path [String] the missing path
      # @return [Array<Hash>]
      def not_found(file_path)
        [{ path: file_path, message: 'File not found' }]
      end

      # Load and cache a schema by type, recording load failures
      #
      # @param schema_type [Symbol] resolver-provided schema type
      # @param errors [Array<Hash>] error sink
      # @return [Hash, nil] the schema, or nil when unavailable
      def load_schema(schema_type, errors)
        @schema_cache[schema_type] ||= @loader.load(schema_type)
      rescue *MISSING_SCHEMA_ERRORS => e
        errors << { message: e.message }
        nil
      end

      # Run the JSON-Schema engine against parsed data
      #
      # Mirrors the soft dependency on the json-schema gem: its absence
      # is reported as a validation error rather than a crash.
      #
      # @param data [Object] parsed YAML content
      # @param schema [Hash] the JSON schema
      # @param file_path [String] file path for error reporting
      # @return [Array<Hash>] empty when the data is valid
      def schema_errors(data, schema, file_path)
        unless defined?(JSON::Validator)
          return [{ path: file_path,
                    message: 'json-schema gem not available for validation' }]
        end

        # Convert to JSON and back to ensure proper format for validator
        json_content = JSON.parse(data.to_json)
        JSON::Validator.validate!(schema, json_content, validate_schema: false)
        []
      rescue JSON::Schema::ValidationError => e
        [{ path: file_path, message: e.message }]
      rescue JSON::Schema::SchemaError => e
        [{ path: file_path, message: "Schema error: #{e.message}" }]
      rescue StandardError => e
        [{ path: file_path, message: "Validation error: #{e.message}" }]
      end
    end
  end
end
