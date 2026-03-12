# frozen_string_literal: true

module Ammitto
  module Data
    module China
      # Determines which schema to use for a given file
      #
      # SchemaResolver analyzes file paths and content to determine the appropriate
      # schema type for validation. It uses a priority-based resolution strategy:
      #
      # 1. Check by filename (document-types.yml, organizations.yml)
      # 2. Check by directory path (legal-instruments, sanction-updates)
      # 3. Check by content structure (measure_modifications, sanction_details)
      #
      # @example Resolving schema type
      #   type = SchemaResolver.resolve('sources/sanction-lists/file.yml')
      #   # => :announcement
      #
      #   type = SchemaResolver.resolve('sources/sanction-updates/file.yml', content)
      #   # => :modification
      #
      class SchemaResolver
        # Directories that use modification schema
        MODIFICATION_DIRECTORIES = %w[
          sanction-updates
          unreliable-entity-list-updates
        ].freeze

        # Directories that use legal instrument schema
        LEGAL_INSTRUMENT_DIRECTORIES = %w[
          legal-instruments
        ].freeze

        # Directories that use announcement schema
        ANNOUNCEMENT_DIRECTORIES = %w[
          sanction-lists
          unreliable-entity-list
          export-control-list
          anti-sanction-list
        ].freeze

        # Files that use document types schema
        DOCUMENT_TYPES_FILES = %w[
          document-types.yml
          document-types.yaml
        ].freeze

        # Files that use organizations schema
        ORGANIZATIONS_FILES = %w[
          organizations.yml
          organizations.yaml
        ].freeze

        class << self
          # Determine schema type based on file path and content
          #
          # @param file_path [String] Path to the YAML file
          # @param content [Hash, nil] Parsed YAML content (optional)
          # @return [Symbol, nil] Schema type or nil if cannot be determined
          #
          # Returns one of:
          # - :announcement - Standard sanction announcements
          # - :modification - Temporal modifications (suspend/continue/stop)
          # - :legal_instrument - Legal instruments and laws
          # - :document_types - Document type definitions
          # - :organizations - Organization definitions
          def resolve(file_path, content = nil)
            # 1. Check by filename first (highest priority)
            return :document_types if document_types_file?(file_path)
            return :organizations if organizations_file?(file_path)

            # 2. Check by directory path
            return :legal_instrument if legal_instrument_directory?(file_path)
            return :modification if modification_directory?(file_path)
            return :announcement if announcement_directory?(file_path)

            # 3. Check content if available
            if content.is_a?(Hash)
              return :modification if modification_content?(content)
              return :announcement if announcement_content?(content)
              return :legal_instrument if legal_instrument_content?(content)
              return :document_types if document_types_content?(content)
              return :organizations if organizations_content?(content)
            end

            # Default to announcement for unknown files
            :announcement
          end

          # Check if file is a document types file
          # @param file_path [String] Path to check
          # @return [Boolean] true if it's a document types file
          def document_types_file?(file_path)
            filename = File.basename(file_path).downcase
            DOCUMENT_TYPES_FILES.any? { |f| f == filename }
          end

          # Check if file is an organizations file
          # @param file_path [String] Path to check
          # @return [Boolean] true if it's an organizations file
          def organizations_file?(file_path)
            filename = File.basename(file_path).downcase
            ORGANIZATIONS_FILES.any? { |f| f == filename }
          end

          # Check if file is in a legal-instruments directory
          # @param file_path [String] Path to check
          # @return [Boolean] true if in legal-instruments directory
          def legal_instrument_directory?(file_path)
            normalized_path = file_path.to_s.downcase
            LEGAL_INSTRUMENT_DIRECTORIES.any? { |dir| normalized_path.include?(dir) }
          end

          # Check if file is in a modification-specific directory
          # @param file_path [String] Path to check
          # @return [Boolean] true if in modification directory
          def modification_directory?(file_path)
            normalized_path = file_path.to_s.downcase
            MODIFICATION_DIRECTORIES.any? { |dir| normalized_path.include?(dir) }
          end

          # Check if file is in an announcement directory
          # @param file_path [String] Path to check
          # @return [Boolean] true if in announcement directory
          def announcement_directory?(file_path)
            normalized_path = file_path.to_s.downcase
            ANNOUNCEMENT_DIRECTORIES.any? { |dir| normalized_path.include?(dir) }
          end

          # Check if content has measure_modifications key
          # @param content [Hash] Parsed YAML content
          # @return [Boolean] true if content indicates modification
          def modification_content?(content)
            content.is_a?(Hash) && content.key?('measure_modifications')
          end

          # Check if content has sanction_details key
          # @param content [Hash] Parsed YAML content
          # @return [Boolean] true if content indicates announcement
          def announcement_content?(content)
            content.is_a?(Hash) && content.key?('sanction_details')
          end

          # Check if content has legal instrument structure
          # @param content [Hash] Parsed YAML content
          # @return [Boolean] true if content indicates legal instrument
          def legal_instrument_content?(content)
            content.is_a?(Hash) &&
              content.key?('title') &&
              content.key?('content')
          end

          # Check if content has document_types key
          # @param content [Hash] Parsed YAML content
          # @return [Boolean] true if content indicates document types
          def document_types_content?(content)
            content.is_a?(Hash) && content.key?('document_types')
          end

          # Check if content has organizations key
          # @param content [Hash] Parsed YAML content
          # @return [Boolean] true if content indicates organizations
          def organizations_content?(content)
            content.is_a?(Hash) && content.key?('organizations')
          end
        end
      end
    end
  end
end
