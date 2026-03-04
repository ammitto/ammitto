# frozen_string_literal: true

require 'yaml'
begin
  require 'json-schema'
rescue LoadError
  # json-schema not available - validation will be skipped
end

module Ammitto
  module Data
    module China
      # Validates China source YAML files against JSON schemas
      #
      # @example Validate a file
      #   validator = Validator.new
      #   if validator.validate('path/to/file.yml')
      #     puts "Valid!"
      #   else
      #     puts validator.errors
      #   end
      #
      class Validator
        attr_reader :schemas_dir, :errors

        def initialize(schemas_dir = nil)
          @schemas_dir = schemas_dir || default_schemas_dir
          @errors = []
        end

        # Validate a single YAML file
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

          schema_type = determine_schema_type(file_path, data)
          return false if schema_type.nil?

          schema = load_schema(schema_type)
          return false if schema.nil?

          validate_against_schema(data, schema, file_path)
        end

        # Validate all files in sources directory
        # @param sources_dir [String] Path to sources directory
        # @return [Hash] Validation report
        def validate_all(sources_dir = nil)
          sources_dir ||= File.join(File.dirname(@schemas_dir), 'sources')
          report = {
            total_files: 0,
            valid_files: 0,
            invalid_files: 0,
            errors: []
          }

          yaml_files = Dir.glob(File.join(sources_dir, '**', '*.yml')) +
                       Dir.glob(File.join(sources_dir, '**', '*.yaml'))

          yaml_files.each do |file|
            report[:total_files] += 1
            if validate(file)
              report[:valid_files] += 1
            else
              report[:invalid_files] += 1
              report[:errors] << { file: file, errors: @errors.dup }
            end
          end

          report
        end

        private

        def default_schemas_dir
          File.expand_path('..', __dir__)
        end

        def load_yaml(file_path)
          YAML.safe_load_file(file_path, permitted_classes: [Date, Time], aliases: true)
        rescue Psych::SyntaxError => e
          @errors << { path: file_path, message: "YAML syntax error: #{e.message}" }
          nil
        end

        def determine_schema_type(file_path, data)
          if file_path.include?('sanction-updates') || file_path.include?('measure_modifications')
            'cn-measure-modification'
          elsif file_path.include?('sanction-lists')
            'cn-announcement'
          elsif file_path.include?('legal-instruments')
            'cn-legal-instrument'
          elsif data.key?('measure_modifications')
            'cn-measure-modification'
          elsif data.key?('sanction_details')
            'cn-announcement'
          elsif data.key?('content') && data.key?('type') &&
                %w[法律 命令 规定 条例].any? { |t| data['type'].include?(t) }
            'cn-legal-instrument'
          else
            @errors << { path: file_path, message: 'Cannot determine schema type' }
            nil
          end
        end

        def load_schema(schema_type)
          schema_file = File.join(@schemas_dir, "#{schema_type}.yml")
          unless File.exist?(schema_file)
            @errors << { message: "Schema not found: #{schema_type}" }
            return nil
          end

          YAML.safe_load_file(schema_file, permitted_classes: [Date, Time])
        rescue StandardError => e
          @errors << { message: "Failed to load schema #{schema_type}: #{e.message}" }
          nil
        end

        def validate_against_schema(data, schema, file_path)
          unless defined?(JSON::Validator)
            @errors << { path: file_path, message: 'json-schema gem not available for validation' }
            return false
          end

          begin
            JSON::Validator.validate!(schema, data)
            true
          rescue JSON::Schema::ValidationError => e
            @errors << { path: file_path, message: e.message }
            false
          rescue JSON::Schema::SchemaError => e
            @errors << { path: file_path, message: "Schema error: #{e.message}" }
            false
          end
        end
      end
    end
  end
end
