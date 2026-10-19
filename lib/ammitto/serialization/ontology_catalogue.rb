# frozen_string_literal: true

require 'json'
require_relative '../schema/context'

module Ammitto
  module Serialization
    # Browser metadata projected from the canonical publication contract.
    class OntologyCatalogue
      SCHEMA_PATH = File.expand_path('../../../schemas/output/v1/outputs.schema.json', __dir__)
      ENTITY_CLASSES = %w[PersonEntity OrganizationEntity VesselEntity AircraftEntity].freeze
      # References without an inline @type need their relationship semantics.
      REFERENCE_RANGES = {
        'hasSanctionEntry' => 'SanctionEntry', 'authority' => 'Authority',
        'regime' => 'SanctionRegime', 'legalBases' => 'LegalInstrument'
      }.freeze

      def self.publication_iri(term)
        context = Schema::Context.context.fetch('@context')
        definition = context.fetch(term, term)
        value = definition.is_a?(Hash) ? definition.fetch('@id', term) : definition
        prefix, suffix = value.split(':', 2)
        return context[prefix] + suffix if suffix && context[prefix].is_a?(String)
        return value if suffix

        context.fetch('@vocab') + value
      end

      def initialize
        @definitions = JSON.parse(File.read(SCHEMA_PATH)).fetch('definitions')
        # Canonical definitions are named by their wire @type. Exclude special
        # example schemas, indices and alternate inline subsets of a class.
        @typed = @definitions.select do |name, schema|
          types = schema.dig('properties', '@type', 'enum')
          types && (types == [name] || name == 'localizedString')
        end
        @common = ENTITY_CLASSES.map { |name| fields(@typed.fetch(name)).keys }.reduce(:&)
      end

      def classes
        base = { id: 'Entity', label: 'Entity', comment: 'Common fields of sanctionable entities',
                 parent: nil, properties: @common }
        [base] + @typed.map do |_name, schema|
          id = schema.dig('properties', '@type', 'enum').first
          { id: id, label: label(id), comment: "Canonical #{label(id).downcase} publication fields",
            parent: ENTITY_CLASSES.include?(id) ? 'Entity' : nil,
            properties: fields(schema).keys }
        end
      end

      def properties
        occurrences = Hash.new { |hash, key| hash[key] = [] }
        @typed.each_value do |schema|
          id = schema.dig('properties', '@type', 'enum').first
          fields(schema).each { |name, value| occurrences[name] << [id, value] }
        end
        occurrences.map do |name, uses|
          domains = uses.map(&:first)
          domain = if (domains - ENTITY_CLASSES).empty? && @common.include?(name)
                     'Entity'
                   elsif domains.size == 1
                     domains.first
                   end
          ranges = uses.map { |_id, schema| range(schema, name) }.uniq
          context_term = Schema::Context.context.fetch('@context')[name]
          datatype = context_term['@type'] if context_term.is_a?(Hash)
          resolved_range = ranges.one? ? ranges.first : nil
          resolved_range = 'SanctionEntry' if name == 'hasSanctionEntry'
          resolved_range = datatype.delete_prefix('xsd:') if datatype&.start_with?('xsd:')
          # A context vocabulary coercion publishes IRIs rather than strings.
          resolved_range = nil if %w[@vocab @id].include?(datatype) && !REFERENCE_RANGES.key?(name)
          { id: name, label: label(name), comment: "Canonical #{name} field",
            domain: domain, range: resolved_range,
            usages: uses.map do |class_id, schema|
              usage_range = range(schema, name)
              usage_range = 'SanctionEntry' if name == 'hasSanctionEntry'
              usage_range = datatype.delete_prefix('xsd:') if datatype&.start_with?('xsd:')
              { class: class_id, range: usage_range, isArray: schema['type'] == 'array' }.compact
            end,
            array: uses.all? { |_id, schema| schema['type'] == 'array' } }
        end
      end

      private

      def fields(schema)
        schema.fetch('properties').reject { |name, _| name.start_with?('@') }
      end

      def label(name)
        name.gsub(/([a-z])([A-Z])/, '\\1 \\2').split.map(&:capitalize).join(' ')
      end

      def range(schema, property = nil)
        return range(schema.fetch('items'), property) if schema['type'] == 'array'

        if schema['$ref']
          target = @definitions.fetch(schema['$ref'].split('/').last)
          return REFERENCE_RANGES[property] if %w[reference regimeReference].include?(schema['$ref'].split('/').last)

          return target.dig('properties', '@type', 'enum')&.first || range(target, property)
        end
        alternatives = schema['anyOf'] || schema['oneOf']
        if alternatives
          ranges = alternatives.map { |item| range(item, property) }.uniq
          return ranges.first if ranges.one?

          return nil
        end
        return schema['type'] if %w[string integer number boolean].include?(schema['type'])
        return 'string' if schema['enum']&.all?(String)

        nil
      end
    end
  end
end
