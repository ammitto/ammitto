# frozen_string_literal: true

require 'json'

module Ammitto
  module Schema
    # Validator validates JSON-LD data against Ammitto schemas
    #
    # @example Validating a sanction entry
    #   validator = Ammitto::Schema::Validator.new
    #   validator.validate_sanction_entry(data)
    #
    class Validator
      # Required fields for SanctionEntry
      SANCTION_ENTRY_REQUIRED = %w[id entityId authority status].freeze

      # Required fields for Entity
      ENTITY_REQUIRED = %w[id entityType names].freeze

      # Valid entity types
      ENTITY_TYPES = %w[person organization vessel aircraft].freeze

      # Valid statuses
      STATUSES = StatusChange::STATUSES

      # Validate a sanction entry
      # @param data [Hash] the entry data to validate
      # @return [Array<String>] list of validation errors
      def validate_sanction_entry(data)
        errors = []

        # Check required fields
        SANCTION_ENTRY_REQUIRED.each do |field|
          value = field_to_value(data, field)
          errors << "Missing required field: #{field}" if value.nil? || value.empty?
        end

        # Validate status
        status = field_to_value(data, 'status')
        errors << "Invalid status: #{status}" if status && !STATUSES.include?(status)

        # Validate authority
        authority = data['authority']
        if authority.is_a?(Hash)
          auth_id = authority['id']
          errors << "Unknown authority: #{auth_id}" if auth_id && !Authority::REGISTRY.key?(auth_id)
        end

        errors
      end

      # Validate an entity
      # @param data [Hash] the entity data to validate
      # @return [Array<String>] list of validation errors
      def validate_entity(data)
        errors = []

        # Check required fields
        ENTITY_REQUIRED.each do |field|
          value = field_to_value(data, field)
          errors << "Missing required field: #{field}" if value.nil? || value.empty?
        end

        # Validate entity type
        entity_type = field_to_value(data, 'entityType')
        errors << "Invalid entity type: #{entity_type}" if entity_type && !ENTITY_TYPES.include?(entity_type)

        # Validate names array
        names = data['names']
        if names.is_a?(Array)
          if names.empty?
            errors << 'Entity must have at least one name'
          else
            names.each_with_index do |name, idx|
              errors.concat(validate_name_variant(name, "names[#{idx}]"))
            end
          end
        end

        errors
      end

      # Validate a name variant
      # @param data [Hash] the name data
      # @param prefix [String] prefix for error messages
      # @return [Array<String>] list of validation errors
      def validate_name_variant(data, prefix = 'name')
        errors = []

        return errors unless data.is_a?(Hash)

        # Must have at least one name component
        has_name = %w[fullName firstName lastName].any? do |field|
          v = data[field]
          v && !v.empty?
        end

        errors << "#{prefix}: Must have fullName, firstName, or lastName" unless has_name

        errors
      end

      # Validate JSON-LD structure
      # @param data [Hash] the JSON-LD data
      # @return [Array<String>] list of validation errors
      def validate_json_ld(data)
        errors = []

        # Check for @context
        errors << 'Missing @context in JSON-LD' unless data.key?('@context')

        # Check for @graph or @type
        errors << 'JSON-LD must have @graph or @type' unless data.key?('@graph') || data.key?('@type')

        errors
      end

      private

      # Get field value handling camelCase/snake_case
      def field_to_value(data, field)
        # Try exact match first
        return data[field] if data.key?(field)

        # Try snake_case version
        snake = camel_to_snake(field)
        return data[snake] if data.key?(snake)

        nil
      end

      # Convert camelCase to snake_case
      def camel_to_snake(str)
        str.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, '')
      end
    end
  end
end
