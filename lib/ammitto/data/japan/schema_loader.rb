# frozen_string_literal: true

require 'yaml'

module Ammitto
  module Data
    module Japan
      # Loads and caches JSON schemas for Japan sanctions data validation
      #
      # SchemaLoader provides a centralized way to load JSON schemas used for
      # validating Japan sanctions data. Schemas are loaded from the schemas/japan
      # directory within the gem.
      #
      # @example Loading a schema
      #   schema = SchemaLoader.load(:announcement)
      #   schema = SchemaLoader.load(:legal_instrument)
      #
      class SchemaLoader
        # Path to schemas directory (ammitto/schemas/japan)
        SCHEMAS_DIR = File.expand_path('../../../../schemas/japan', __dir__)

        # Schema type to filename mapping
        SCHEMA_FILES = {
          announcement: 'jp-announcement.yml',
          legal_instrument: 'jp-legal-instrument.yml',
          document_type: 'jp-document-type.yml',
          document_types: 'document-types.yml',
          organizations: 'organizations.yml'
        }.freeze

        class << self
          # Load a schema by type
          # @param schema_type [Symbol] The schema type (:announcement, :legal_instrument, etc.)
          # @return [Hash] The loaded schema
          # @raise [SchemaNotFoundError] If the schema file doesn't exist
          def load(schema_type)
            filename = SCHEMA_FILES[schema_type]
            raise SchemaNotFoundError, "Unknown schema type: #{schema_type}" unless filename

            schema_path = File.join(SCHEMAS_DIR, filename)
            raise SchemaNotFoundError, "Schema not found: #{schema_path}" unless File.exist?(schema_path)

            YAML.safe_load_file(schema_path, permitted_classes: [Date, Time])
          end

          # Load the announcement schema
          # @return [Hash] The announcement schema
          def load_announcement_schema
            load(:announcement)
          end

          # Load the legal instrument schema
          # @return [Hash] The legal instrument schema
          def load_legal_instrument_schema
            load(:legal_instrument)
          end

          # Load the document types schema
          # @return [Hash] The document types schema
          def load_document_types_schema
            load(:document_types)
          end

          # Load the organizations schema
          # @return [Hash] The organizations schema
          def load_organizations_schema
            load(:organizations)
          end

          # Check if a schema type is supported
          # @param schema_type [Symbol] The schema type to check
          # @return [Boolean] true if the schema type is supported
          def supported?(schema_type)
            SCHEMA_FILES.key?(schema_type)
          end

          # List all supported schema types
          # @return [Array<Symbol>] List of supported schema types
          def supported_types
            SCHEMA_FILES.keys
          end
        end
      end

      # Error raised when a schema cannot be found
      class SchemaNotFoundError < StandardError; end
    end
  end
end
