# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'
require_relative 'json_ld_serializer'
require_relative 'turtle_exporter'

module Ammitto
  module Serialization
    # JsonLdGraphExporter exports Ammitto data as a proper JSON-LD knowledge graph
    #
    # This class collects nodes during harmonization and exports them as:
    # - Individual JSON-LD node files per entity, entry, instrument, regime, authority
    # - Aggregated files (all.jsonld, all.ttl)
    # - Index files for each node type
    #
    # @example Using the graph exporter
    #   exporter = JsonLdGraphExporter.new(output_dir: './api/v1')
    #
    #   # Add nodes during harmonization
    #   exporter.add_node(entity: entity_hash, entry: entry_hash, source: :un)
    #
    #   # Export all nodes
    #   exporter.export
    #
    class JsonLdGraphExporter
      # Base URI for all node IDs
      BASE_URI = 'https://www.ammitto.org'

      # @return [String] output directory
      attr_reader :output_dir

      # @return [String] context URL
      attr_reader :context_url

      # @return [Hash] collected entities keyed by ID
      attr_reader :entities

      # @return [Hash] collected entries keyed by ID
      attr_reader :entries

      # @return [Hash] collected instruments keyed by ID
      attr_reader :instruments

      # @return [Hash] collected regimes keyed by code
      attr_reader :regimes

      # @return [Hash] collected authorities keyed by code
      attr_reader :authorities

      # @return [Hash] statistics
      attr_reader :stats

      # Initialize the graph exporter
      # @param output_dir [String] directory for output files
      # @param context_url [String] URL to the JSON-LD context
      def initialize(output_dir:, context_url: nil)
        @output_dir = output_dir
        @context_url = context_url || "#{BASE_URI}/ontology/context.jsonld"

        # Node collectors
        @entities = {}
        @entries = {}
        @instruments = {}
        @regimes = {}
        @authorities = {}

        # Statistics tracking
        @stats = {
          generated_at: Time.now.utc.iso8601,
          sources: {},
          total_entities: 0,
          total_entries: 0,
          total_instruments: 0,
          total_regimes: 0,
          total_authorities: 0
        }

        # Serializer for generating node data
        @serializer = JsonLdSerializer.new
      end

      # Add a transformed result to the graph
      # @param entity [Hash] entity hash
      # @param entry [Hash] entry hash
      # @param source [Symbol] source code
      def add_node(entity:, entry:, source:)
        return unless entity && entry

        source_code = source.to_s.downcase

        # Store entity
        entity_id = entity['@id'] || entity['id']
        if entity_id
          @entities[entity_id] = entity
          @stats[:total_entities] += 1
        end

        # Store entry
        entry_id = entry['@id'] || entry['id']
        if entry_id
          @entries[entry_id] = entry
          @stats[:total_entries] += 1
        end

        # Track source stats
        @stats[:sources][source_code] ||= { entities: 0, entries: 0 }
        @stats[:sources][source_code][:entities] += 1
        @stats[:sources][source_code][:entries] += 1

        # Extract and deduplicate shared nodes
        extract_authority(entry, source_code)
        extract_regime(entry)
        extract_instruments(entry, source_code)
      end

      # Export all nodes to files
      # @return [void]
      def export
        create_directories

        export_authority_nodes
        export_regime_nodes
        export_instrument_nodes
        export_entity_nodes
        export_entry_nodes

        export_index_files
        export_data_slices
        export_aggregated_files
        export_stats
        copy_context_file

        return unless ENV['VERBOSE']

        puts "Exported #{@entities.length} entities, #{@entries.length} entries, " \
             "#{@instruments.length} instruments, #{@regimes.length} regimes, " \
             "#{@authorities.length} authorities"
      end

      private

      # Create the directory structure for node files
      # @return [void]
      def create_directories
        dirs = [
          File.join(@output_dir, 'node', 'entity'),
          File.join(@output_dir, 'node', 'entry'),
          File.join(@output_dir, 'node', 'instrument'),
          File.join(@output_dir, 'node', 'regime'),
          File.join(@output_dir, 'node', 'authority'),
          File.join(@output_dir, 'by-authority'),
          File.join(@output_dir, 'by-regime'),
          File.join(@output_dir, 'by-status'),
          File.join(@output_dir, 'by-type')
        ]

        dirs.each { |dir| FileUtils.mkdir_p(dir) }
      end

      # Extract authority from entry and deduplicate
      # @param entry [Hash] entry hash
      # @param source_code [String] source code
      # @return [void]
      def extract_authority(entry, source_code)
        authority = entry['authority']
        return unless authority

        # Get authority code
        code = authority['countryCode'] || authority['id'] || source_code
        return unless code

        auth_id = "#{BASE_URI}/authority/#{code.to_s.downcase}"

        # Store full authority if not already present
        @authorities[code.to_s.downcase] ||= {
          '@context' => @context_url,
          '@id' => auth_id,
          '@type' => 'Authority',
          'name' => authority['name'],
          'countryCode' => code.to_s.upcase,
          'url' => authority['url']
        }.compact

        # Replace entry authority with @id reference
        entry['authority'] = { '@id' => auth_id }

        @stats[:total_authorities] = @authorities.length
      end

      # Extract regime from entry and deduplicate
      # @param entry [Hash] entry hash
      # @return [void]
      def extract_regime(entry)
        regime = entry['regime']
        return unless regime

        code = regime['code']
        return unless code

        code_lower = code.to_s.downcase
        regime_id = "#{BASE_URI}/regime/#{code_lower}"

        # Store full regime if not already present
        @regimes[code_lower] ||= {
          '@context' => @context_url,
          '@id' => regime_id,
          '@type' => 'SanctionRegime',
          'name' => regime['name'],
          'code' => code.to_s.upcase,
          'description' => regime['description']
        }.compact

        # Replace entry regime with @id reference
        entry['regime'] = { '@id' => regime_id }

        @stats[:total_regimes] = @regimes.length
      end

      # Extract legal instruments from entry and deduplicate
      # @param entry [Hash] entry hash
      # @param source_code [String] source code
      # @return [void]
      def extract_instruments(entry, source_code)
        bases = entry['legalBases']
        return unless bases&.any?

        entry['legalBases'] = bases.map do |base|
          next base unless base.is_a?(Hash)

          identifier = base['identifier']
          next base unless identifier

          # Create a normalized identifier for the ID
          normalized_id = normalize_identifier(identifier)
          instrument_id = "#{BASE_URI}/instrument/#{source_code}/#{normalized_id}"

          # Store full instrument if not already present
          @instruments[instrument_id] ||= {
            '@context' => @context_url,
            '@id' => instrument_id,
            '@type' => 'LegalInstrument',
            'type' => base['type'],
            'identifier' => identifier,
            'title' => base['title'],
            'issuingBody' => base['issuingBody'],
            'issuanceDate' => base['issuanceDate'],
            'url' => base['url']
          }.compact

          # Return @id reference
          { '@id' => instrument_id }
        end

        @stats[:total_instruments] = @instruments.length
      end

      # Normalize an identifier for use in URIs
      # @param identifier [String] the identifier
      # @return [String] normalized identifier
      def normalize_identifier(identifier)
        identifier.to_s
                  .gsub(%r{[/\\]}, '-')
                  .gsub(/[^a-zA-Z0-9\-._]/, '-')
                  .gsub(/-+/, '-')
                  .gsub(/^-|-$/, '')
                  .downcase
      end

      # Export entity node files
      # @return [void]
      def export_entity_nodes
        by_source = group_by_source(@entities)

        by_source.each do |source, entities|
          source_dir = File.join(@output_dir, 'node', 'entity', source)
          FileUtils.mkdir_p(source_dir)

          entities.each do |id, entity|
            ref = extract_ref_from_id(id, 'entity')
            next unless ref

            path = File.join(source_dir, "#{ref}.jsonld")
            node = entity.merge('@context' => @context_url)
            write_json(path, node)
          end
        end
      end

      # Export entry node files
      # @return [void]
      def export_entry_nodes
        by_source = group_by_source(@entries)

        by_source.each do |source, entries|
          source_dir = File.join(@output_dir, 'node', 'entry', source)
          FileUtils.mkdir_p(source_dir)

          entries.each do |id, entry|
            ref = extract_ref_from_id(id, 'entry')
            next unless ref

            path = File.join(source_dir, "#{ref}.jsonld")
            node = entry.merge('@context' => @context_url)
            write_json(path, node)
          end
        end
      end

      # Export instrument node files
      # @return [void]
      def export_instrument_nodes
        by_source = group_instruments_by_source

        by_source.each do |source, instruments|
          source_dir = File.join(@output_dir, 'node', 'instrument', source)
          FileUtils.mkdir_p(source_dir)

          instruments.each do |id, instrument|
            identifier = extract_instrument_identifier(id)
            next unless identifier

            path = File.join(source_dir, "#{identifier}.jsonld")
            write_json(path, instrument)
          end
        end
      end

      # Export regime node files
      # @return [void]
      def export_regime_nodes
        @regimes.each do |code, regime|
          path = File.join(@output_dir, 'node', 'regime', "#{code}.jsonld")
          write_json(path, regime)
        end
      end

      # Export authority node files
      # @return [void]
      def export_authority_nodes
        @authorities.each do |code, authority|
          path = File.join(@output_dir, 'node', 'authority', "#{code}.jsonld")
          write_json(path, authority)
        end
      end

      # Export index files for each node type
      # @return [void]
      def export_index_files
        # Entity index
        entity_index = {
          '@context' => @context_url,
          '@type' => 'Index',
          'nodes' => @entities.keys.sort.map { |id| { '@id' => id } }
        }
        write_json(File.join(@output_dir, 'node', 'entity', 'index.jsonld'), entity_index)

        # Entry index
        entry_index = {
          '@context' => @context_url,
          '@type' => 'Index',
          'nodes' => @entries.keys.sort.map { |id| { '@id' => id } }
        }
        write_json(File.join(@output_dir, 'node', 'entry', 'index.jsonld'), entry_index)

        # Instrument index
        instrument_index = {
          '@context' => @context_url,
          '@type' => 'Index',
          'nodes' => @instruments.keys.sort.map { |id| { '@id' => id } }
        }
        write_json(File.join(@output_dir, 'node', 'instrument', 'index.jsonld'), instrument_index)

        # Regime index
        regime_index = {
          '@context' => @context_url,
          '@type' => 'Index',
          'nodes' => @regimes.keys.sort.map { |code| { '@id' => "#{BASE_URI}/regime/#{code}" } }
        }
        write_json(File.join(@output_dir, 'node', 'regime', 'index.jsonld'), regime_index)

        # Authority index
        authority_index = {
          '@context' => @context_url,
          '@type' => 'Index',
          'nodes' => @authorities.keys.sort.map { |code| { '@id' => "#{BASE_URI}/authority/#{code}" } }
        }
        write_json(File.join(@output_dir, 'node', 'authority', 'index.jsonld'), authority_index)
      end

      # Export aggregated files
      # @return [void]
      def export_aggregated_files
        # Export all.jsonld with all nodes
        all_graph = []
        all_graph.concat(@authorities.values)
        all_graph.concat(@regimes.values)
        all_graph.concat(@instruments.values)
        all_graph.concat(@entities.values.map { |e| e.merge('@context' => @context_url) })
        all_graph.concat(@entries.values.map { |e| e.merge('@context' => @context_url) })

        all_output = {
          '@context' => @context_url,
          '@graph' => all_graph
        }

        all_jsonld_path = File.join(@output_dir, 'all.jsonld')
        write_json(all_jsonld_path, all_output)

        # Export all.ttl (Turtle format)
        all_ttl_path = File.join(@output_dir, 'all.ttl')
        TurtleExporter.export(jsonld_path: all_jsonld_path, output_path: all_ttl_path)
      end

      # Export statistics file
      # @return [void]
      def export_stats
        write_json(File.join(@output_dir, 'stats.json'), @stats)
      end

      # Export data slice index files
      # Creates lightweight index files with @id references grouped by:
      # - Authority (by-authority/{code}.jsonld)
      # - Regime (by-regime/{code}.jsonld)
      # - Status (by-status/{status}.jsonld)
      # - Entity type (by-type/{type}.jsonld)
      # @return [void]
      def export_data_slices
        export_slices_by_authority
        export_slices_by_regime
        export_slices_by_status
        export_slices_by_entity_type
      end

      # Export slices by authority
      # @return [void]
      def export_slices_by_authority
        slices_dir = File.join(@output_dir, 'by-authority')
        FileUtils.mkdir_p(slices_dir)

        # Group entries by authority
        by_authority = {}
        @entries.each_value do |entry|
          auth_ref = entry.dig('authority', '@id')
          next unless auth_ref

          auth_code = auth_ref.split('/').last
          by_authority[auth_code] ||= []
          by_authority[auth_code] << { '@id' => entry['@id'] || entry['id'] }
        end

        # Write index files
        by_authority.each do |code, entries|
          index = {
            '@context' => @context_url,
            '@type' => 'Index',
            'slice' => 'by-authority',
            'authority' => { '@id' => "#{BASE_URI}/authority/#{code}" },
            'entries' => entries
          }
          write_json(File.join(slices_dir, "#{code}.jsonld"), index)
        end

        # Write master index
        master = {
          '@context' => @context_url,
          '@type' => 'Index',
          'slice' => 'by-authority',
          'available' => by_authority.keys.sort.map { |code| "#{BASE_URI}/authority/#{code}" }
        }
        write_json(File.join(slices_dir, 'index.jsonld'), master)
      end

      # Export slices by regime
      # @return [void]
      def export_slices_by_regime
        slices_dir = File.join(@output_dir, 'by-regime')
        FileUtils.mkdir_p(slices_dir)

        # Group entries by regime
        by_regime = {}
        @entries.each_value do |entry|
          regime_ref = entry.dig('regime', '@id')
          next unless regime_ref

          regime_code = regime_ref.split('/').last
          by_regime[regime_code] ||= []
          by_regime[regime_code] << { '@id' => entry['@id'] || entry['id'] }
        end

        # Write index files
        by_regime.each do |code, entries|
          index = {
            '@context' => @context_url,
            '@type' => 'Index',
            'slice' => 'by-regime',
            'regime' => { '@id' => "#{BASE_URI}/regime/#{code}" },
            'entries' => entries
          }
          write_json(File.join(slices_dir, "#{code}.jsonld"), index)
        end

        # Write master index
        master = {
          '@context' => @context_url,
          '@type' => 'Index',
          'slice' => 'by-regime',
          'available' => by_regime.keys.sort.map { |code| "#{BASE_URI}/regime/#{code}" }
        }
        write_json(File.join(slices_dir, 'index.jsonld'), master)
      end

      # Export slices by status
      # @return [void]
      def export_slices_by_status
        slices_dir = File.join(@output_dir, 'by-status')
        FileUtils.mkdir_p(slices_dir)

        # Group entries by status
        by_status = {}
        @entries.each_value do |entry|
          status = entry['status'] || 'unknown'
          by_status[status] ||= []
          by_status[status] << { '@id' => entry['@id'] || entry['id'] }
        end

        # Write index files
        by_status.each do |status, entries|
          index = {
            '@context' => @context_url,
            '@type' => 'Index',
            'slice' => 'by-status',
            'status' => status,
            'entries' => entries
          }
          write_json(File.join(slices_dir, "#{status}.jsonld"), index)
        end

        # Write master index
        master = {
          '@context' => @context_url,
          '@type' => 'Index',
          'slice' => 'by-status',
          'available' => by_status.keys.sort
        }
        write_json(File.join(slices_dir, 'index.jsonld'), master)
      end

      # Export slices by entity type
      # @return [void]
      def export_slices_by_entity_type
        slices_dir = File.join(@output_dir, 'by-type')
        FileUtils.mkdir_p(slices_dir)

        # Group entities by type
        by_type = {}
        @entities.each_value do |entity|
          type = entity['entityType'] || entity['@type'] || 'unknown'
          type_key = type.to_s.downcase.gsub(/entity$/i, '').gsub(/[^a-z0-9]/, '')
          by_type[type_key] ||= []
          by_type[type_key] << { '@id' => entity['@id'] || entity['id'] }
        end

        # Write index files
        by_type.each do |type, entities|
          index = {
            '@context' => @context_url,
            '@type' => 'Index',
            'slice' => 'by-type',
            'entityType' => type,
            'entities' => entities
          }
          write_json(File.join(slices_dir, "#{type}.jsonld"), index)
        end

        # Write master index
        master = {
          '@context' => @context_url,
          '@type' => 'Index',
          'slice' => 'by-type',
          'available' => by_type.keys.sort
        }
        write_json(File.join(slices_dir, 'index.jsonld'), master)
      end

      # Copy context.jsonld to output directory
      # @return [void]
      def copy_context_file
        context_source = find_context_file_path
        return unless context_source

        context_dest = File.join(@output_dir, 'context.jsonld')
        FileUtils.cp(context_source, context_dest)
      end

      # Find the context.jsonld file path
      # @return [String, nil] path to context file or nil
      def find_context_file_path
        # Try gem data directory
        gem_root = begin
          Gem::Specification.find_by_name('ammitto').gem_dir
        rescue StandardError
          nil
        end
        if gem_root
          context_path = File.join(gem_root, 'data', 'ontology', 'context.jsonld')
          return context_path if File.exist?(context_path)
        end

        # Try relative path from lib
        lib_context = File.expand_path('../../../../data/ontology/context.jsonld', __dir__)
        return lib_context if File.exist?(lib_context)

        # Try project root context
        project_context = File.expand_path('data/ontology/context.jsonld')
        return project_context if File.exist?(project_context)

        nil
      end

      # Group nodes by source
      # @param nodes [Hash] nodes keyed by ID
      # @return [Hash] nodes grouped by source code
      def group_by_source(nodes)
        result = {}

        nodes.each_key do |id|
          # Extract source from ID like "https://www.ammitto.org/entity/un/KPi.066"
          match = id.match(%r{#{Regexp.escape(BASE_URI)}/[^/]+/([^/]+)/})
          next unless match

          source = match[1]
          result[source] ||= {}
          result[source][id] = nodes[id]
        end

        result
      end

      # Group instruments by source
      # @return [Hash] instruments grouped by source
      def group_instruments_by_source
        result = {}

        @instruments.each do |id, instrument|
          # Extract source from ID like "https://www.ammitto.org/instrument/un/1718-2006"
          match = id.match(%r{#{Regexp.escape(BASE_URI)}/instrument/([^/]+)/})
          next unless match

          source = match[1]
          result[source] ||= {}
          result[source][id] = instrument
        end

        result
      end

      # Extract reference from entity/entry ID
      # @param id [String] full URI
      # @param type [String] node type (entity or entry)
      # @return [String, nil] reference part
      def extract_ref_from_id(id, type)
        # Extract ref from ID like "https://www.ammitto.org/entity/un/KPi.066"
        match = id.match(%r{#{Regexp.escape(BASE_URI)}/#{type}/[^/]+/(.+)$})
        match ? match[1] : nil
      end

      # Extract identifier from instrument ID
      # @param id [String] full URI
      # @return [String, nil] identifier part
      def extract_instrument_identifier(id)
        # Extract identifier from ID like "https://www.ammitto.org/instrument/un/1718-2006"
        match = id.match(%r{#{Regexp.escape(BASE_URI)}/instrument/[^/]+/(.+)$})
        match ? match[1] : nil
      end

      # Write JSON file
      # @param path [String] file path
      # @param data [Hash] data to write
      # @return [void]
      def write_json(path, data)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(data))
      end
    end
  end
end
