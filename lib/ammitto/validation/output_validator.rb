# frozen_string_literal: true

require 'json'
require 'json-schema'
require 'rdf/turtle'
require 'pathname'
require 'digest/sha2'
require_relative 'result'

module Ammitto
  module Validation
    # Validate bytes written by this run, without treating retained files from
    # an earlier run as current output. Contracts live in the installed gem.
    class OutputValidator
      SCHEMA_PATH = File.expand_path('../../../schemas/output/v1/outputs.schema.json', __dir__)
      NODE_CONTRACTS = %w[
        PersonEntity OrganizationEntity VesselEntity AircraftEntity SanctionEntry
        Authority SanctionRegime LegalInstrument DocumentType Organization
      ].freeze
      ENTITY_CONTRACTS = %w[PersonEntity OrganizationEntity VesselEntity AircraftEntity].freeze
      RECURSIVE_DEFINITION_GROUPS = [
        %w[hierarchyNode], %w[ContentItem],
        %w[Japan_contentItem Japan_chapter Japan_clause Japan_numberedList Japan_listItem]
      ].map(&:freeze).freeze

      # @param output_dir [String] root of the exported API
      def initialize(output_dir:)
        @output_dir = Pathname.new(File.expand_path(output_dir))
        @schema = JSON.parse(File.read(SCHEMA_PATH))
        check_references!(@schema)
        JSON::Validator.validate!(@schema, {}, validate_schema: true)
        @expanded_definitions = @schema.fetch('definitions').to_h do |name, definition|
          [name, expand_references(definition, [name])]
        end
        @contracts = {}
        @validators = {}
        @valid_payloads = {}
        @cache_hits = 0
        @cache_misses = 0
        @node_context = JSON::Validator.new({ 'type' => 'object', 'required' => ['@context'] }, record_errors: true)
        envelope = JSON.parse(JSON.generate(@schema.fetch('definitions').fetch('aggregate')))
        envelope.fetch('properties').fetch('@graph')['items'] = { 'type' => 'object' }
        @aggregate_envelope = JSON::Validator.new(envelope, record_errors: true)
      end

      # @param paths [Array<String>] files the exporters actually wrote
      # @param report [String, nil] optional diagnostic outside the API root
      # @return [Result] file-specific schema or Turtle syntax errors
      def validate_files(paths, report: nil)
        hits_before = @cache_hits
        misses_before = @cache_misses
        files = paths.map { |path| File.expand_path(path) }.uniq
        report_path = File.expand_path(report) if report
        errors = files.flat_map do |path|
          contract = path == report_path ? 'report' : contract_for(path)
          validate_file(path, contract)
        end
        Result.new(errors: errors, details: { files: files.length,
                                              cache_hits: @cache_hits - hits_before,
                                              cache_misses: @cache_misses - misses_before })
      end

      private

      def contract_for(path)
        relative = Pathname.new(path).relative_path_from(@output_dir).to_s
        return nil if relative.start_with?('../')

        case relative
        when 'context.jsonld' then 'context'
        when 'stats.json' then 'stats'
        when 'index.jsonld' then 'catalogue'
        when 'all.jsonld', %r{\Asources/[^/]+\.jsonld\z} then 'aggregate'
        when 'all.ttl', %r{\Asources/[^/]+\.ttl\z} then 'turtle'
        when %r{\Anode/(entity|entry|legal-instrument|regime|authority|group|document-type|organization)/index\.jsonld\z} then 'nodeIndex'
        when %r{\Anode/entity/.+\.jsonld\z} then 'entityFile'
        when %r{\Anode/entry/.+\.jsonld\z} then 'SanctionEntryFile'
        when %r{\Anode/legal-instrument/.+\.jsonld\z} then 'LegalInstrumentFile'
        when %r{\Anode/regime/.+\.jsonld\z} then 'SanctionRegimeFile'
        when %r{\Anode/authority/.+\.jsonld\z} then 'AuthorityFile'
        when %r{\Anode/group/.+\.jsonld\z} then 'group'
        when %r{\Anode/document-type/.+\.jsonld\z} then 'DocumentTypeFile'
        when %r{\Anode/organization/.+\.jsonld\z} then 'OrganizationFile'
        when %r{\Aby-(authority|regime|list|status|type|organization|document-type)/.+\.jsonld\z} then "slice_#{Regexp.last_match(1)}"
        when 'search-index/manifest.json' then 'searchManifest'
        when %r{\Asearch-index/[^/]+\.json\z} then 'searchShard'
        when 'facets/countries.json' then 'facet_countries'
        when 'facets/types.json' then 'facet_types'
        when 'facets/statuses.json' then 'facet_statuses'
        when %r{\Afacets/(authorities|list_types|regimes)\.json\z} then 'facet_other'
        when 'ontology/classes.jsonld' then 'ontologyClasses'
        when 'ontology/properties.jsonld' then 'ontologyProperties'
        when 'ontology/hierarchy.json' then 'hierarchy'
        when %r{\Aontology/examples/(person|organization|vessel)\.jsonld\z} then "example_#{Regexp.last_match(1)}"
        end
      end

      def validate_file(path, contract)
        return [{ path: path, message: 'No output contract registered for artifact' }] unless contract

        if contract == 'turtle'
          RDF::Turtle::Reader.open(path, validate: true, logger: false) do |reader|
            reader.each_statement.count
          end
          return []
        end

        data = JSON.parse(File.read(path))
        # json-schema's instance API resets errors after every validate call.
        # Each contract is compiled once and reused serially within this run.
        messages = contract == 'aggregate' ? validate_aggregate(data) : validate_json(data, contract)
        messages.map do |message|
          { path: path, message: message }
        end
      rescue JSON::ParserError, JSON::Schema::SchemaError, RDF::ReaderError,
             IOError, SystemCallError => e
        [{ path: path, message: "#{e.class}: #{e.message}" }]
      end

      def validate_json(data, contract)
        contract = "#{data['@type']}File" if contract == 'entityFile' && data.is_a?(Hash) && ENTITY_CONTRACTS.include?(data['@type'])
        if contract.end_with?('File') && NODE_CONTRACTS.include?(contract.delete_suffix('File'))
          context_errors = @node_context.validate(data.is_a?(Hash) ? data.slice('@context') : data)
          return context_errors + validate_json(data, contract.delete_suffix('File'))
        end

        if NODE_CONTRACTS.include?(contract)
          # Reuse only a success for the same contract and complete parsed
          # JSON payload. Every file/envelope is still read and checked.
          key = [contract, Digest::SHA256.digest(JSON.generate(data))]
          if @valid_payloads.key?(key)
            @cache_hits += 1
            return []
          end
          @cache_misses += 1
        end

        validator = @validators[contract] ||= JSON::Validator.new(schema_for(contract), record_errors: true)
        errors = validator.validate(data)
        @valid_payloads[key] = true if key && errors.empty?
        errors
      end

      # Equivalent to aggregate's typed union, with exhaustive discriminator
      # dispatch so large graphs do not validate each node against ten types.
      # The envelope is only a first step: every node must pass its full schema.
      def validate_aggregate(data)
        messages = @aggregate_envelope.validate(data)
        return messages unless data.is_a?(Hash) && data['@graph'].is_a?(Array)

        data['@graph'].each_with_index do |node, index|
          type = node.is_a?(Hash) ? node['@type'] : nil
          errors = if NODE_CONTRACTS.include?(type)
                     validate_json(node, type)
                   else
                     ["Unknown or missing node @type #{type.inspect}"]
                   end
          messages.concat(errors.map { |error| "At #/@graph/#{index}: #{error}" })
        end
        messages
      end

      # Resolve non-recursive local references once. json-schema otherwise
      # normalizes and resolves their URIs for every nested value in every
      # record. Recursive hierarchy references retain their definitions.
      def schema_for(contract)
        @contracts[contract] ||= begin
          schema = @expanded_definitions.fetch(contract)
          definitions = {}
          pending = referenced_definitions(schema)
          until pending.empty?
            name = pending.pop
            next if definitions.key?(name)

            definition = @expanded_definitions.fetch(name)
            definitions[name] = definition
            pending.concat(referenced_definitions(definition))
          end
          schema.merge('$schema' => @schema.fetch('$schema'), 'definitions' => definitions)
        end
      end

      def referenced_definitions(schema)
        JSON.generate(schema).scan(%r{"\$ref":"#/definitions/([^"]+)"}).flatten
      end

      def expand_references(value, stack)
        case value
        when Hash
          reference = value['$ref']
          if reference&.start_with?('#/definitions/')
            name = reference.delete_prefix('#/definitions/')
            if stack.include?(name)
              cycle = stack.drop(stack.index(name))
              return value if RECURSIVE_DEFINITION_GROUPS.any? { |group| (cycle - group).empty? }

              raise JSON::Schema::SchemaError, "Cyclic output schema reference: #{(stack + [name]).join(' -> ')}"
            end

            return expand_references(@schema.fetch('definitions').fetch(name), stack + [name])
          end
          value.transform_values { |child| expand_references(child, stack) }
        when Array
          value.map { |child| expand_references(child, stack) }
        else
          value
        end
      end

      # $ref siblings differ across validators. Require explicit allOf for
      # combined constraints so optimization cannot silently drop a sibling.
      def check_references!(value)
        case value
        when Hash
          if value.key?('$ref')
            reference = value['$ref']
            unless value.keys == ['$ref'] && reference.is_a?(String) &&
                   reference.start_with?('#/definitions/')
              raise JSON::Schema::SchemaError, 'Output schema references must be local, $ref-only objects; use allOf for combined constraints'
            end

            name = reference.delete_prefix('#/definitions/')
            raise JSON::Schema::SchemaError, "Unresolved output schema reference: #{reference}" unless @schema.fetch('definitions').key?(name)
          end
          value.each_value { |child| check_references!(child) }
        when Array
          value.each { |child| check_references!(child) }
        end
      end
    end
  end
end
