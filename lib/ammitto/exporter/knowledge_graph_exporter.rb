# frozen_string_literal: true

require 'json'
require 'fileutils'

module Ammitto
  module Exporter
    # KnowledgeGraphExporter exports data from data-* repositories
    # to harmonized JSON-LD format for the website
    #
    # @example Exporting all sources
    #   exporter = Ammitto::Exporter::KnowledgeGraphExporter.new('/Users/mulgogi/src/ammitto')
    #   exporter.export_all(output_dir: '/path/to/output')
    #
    class KnowledgeGraphExporter
      # Data source directories
      DATA_SOURCES = %w[
        data-au data-ca data-ch data-cn data-eu data-eu-vessels
        data-jp data-nz data-ru data-tr data-uk data-un
        data-un-vessels data-us data-wb
      ].freeze

      attr_reader :base_dir, :output_dir

      # Initialize a new KnowledgeGraphExporter
      #
      # @param base_dir [String] Base directory containing data-* repos
      # @param output_dir [String] Output directory for harmonized data
      def initialize(base_dir, output_dir: nil)
        @base_dir = base_dir
        @output_dir = output_dir || File.join(base_dir, 'ammitto.github.io', 'api', 'v1')
      end

      # Export all data sources
      #
      # @return [Hash] Export results
      def export_all
        results = {
          sources: {},
          total_entities: 0,
          total_entries: 0,
          errors: []
        }

        # Ensure output directory exists
        FileUtils.mkdir_p(output_dir)
        FileUtils.mkdir_p(File.join(output_dir, 'sources'))

        all_entities = []
        all_entries = []
        all_announcements = []
        all_legal_instruments = []

        DATA_SOURCES.each do |source_name|
          processed_dir = File.join(base_dir, source_name, 'processed')
          next unless File.directory?(processed_dir)

          # Check if it has knowledge graph structure
          next unless knowledge_graph_structure?(processed_dir)

          begin
            loader = Ammitto::Data::KnowledgeGraphLoader.new(processed_dir)
            harmonized = loader.to_harmonized

            source_code = loader.source_code
            stats = loader.stats

            results[:sources][source_code] = stats
            results[:total_entities] += stats[:entities]
            results[:total_entries] += stats[:entries]

            # Collect for combined export
            all_entities.concat(harmonized[:entities])
            all_entries.concat(harmonized[:entries])
            all_announcements.concat(harmonized[:announcements])
            all_legal_instruments.concat(harmonized[:legal_instruments])

            # Export individual source
            export_source(source_code, harmonized)
          rescue StandardError => e
            results[:errors] << "#{source_name}: #{e.message}"
          end
        end

        # Export combined data
        export_combined(all_entities, all_entries, all_announcements, all_legal_instruments)

        # Export stats
        export_stats(results)

        results
      end

      # Export a single source
      #
      # @param source_code [String] Source code
      # @param harmonized [Hash] Harmonized data
      def export_source(source_code, harmonized)
        source_file = File.join(output_dir, 'sources', "#{source_code}.jsonld")

        graph = []
        graph.concat(harmonized[:entities])
        graph.concat(harmonized[:entries])
        graph.concat(harmonized[:announcements])
        graph.concat(harmonized[:legal_instruments])

        data = {
          '@context' => context,
          '@graph' => graph
        }

        File.write(source_file, JSON.pretty_generate(data))
      end

      # Export combined data from all sources
      #
      # @param entities [Array<Hash>] All entities
      # @param entries [Array<Hash>] All entries
      # @param announcements [Array<Hash>] All announcements
      # @param legal_instruments [Array<Hash>] All legal instruments
      def export_combined(entities, entries, announcements, legal_instruments)
        all_file = File.join(output_dir, 'all.jsonld')

        graph = []
        graph.concat(entities)
        graph.concat(entries)
        graph.concat(announcements)
        graph.concat(legal_instruments)

        data = {
          '@context' => context,
          '@graph' => graph
        }

        File.write(all_file, JSON.pretty_generate(data))
      end

      # Export statistics
      #
      # @param results [Hash] Export results
      def export_stats(results)
        stats_file = File.join(output_dir, 'stats.json')

        stats = {
          generated_at: Time.now.utc.iso8601,
          total_entities: results[:total_entities],
          total_entries: results[:total_entries],
          sources: results[:sources].transform_values do |s|
            {
              entities: s[:entities],
              entries: s[:entries],
              announcements: s[:announcements],
              legal_instruments: s[:legal_instruments]
            }
          end
        }

        File.write(stats_file, JSON.pretty_generate(stats))
      end

      private

      def knowledge_graph_structure?(processed_dir)
        entities_dir = File.join(processed_dir, 'entities')
        entries_dir = File.join(processed_dir, 'entries')

        File.directory?(entities_dir) && File.directory?(entries_dir)
      end

      def context
        {
          '@vocab' => 'https://www.ammitto.org/ontology/',
          'id' => '@id',
          'type' => '@type',
          'entity_type' => { '@id' => 'entityType', '@type' => '@vocab' },
          'names' => { '@id' => 'name', '@container' => '@set' },
          'full_name' => 'name',
          'is_primary' => 'isPrimaryName',
          'script' => 'script',
          'status' => 'entryStatus',
          'listed_date' => { '@id' => 'listedDate', '@type' => 'http://www.w3.org/2001/XMLSchema#date' },
          'delisted_date' => { '@id' => 'delistedDate', '@type' => 'http://www.w3.org/2001/XMLSchema#date' },
          'measures' => { '@id' => 'measure', '@container' => '@set' },
          'source' => 'dataSource',
          'source_url' => 'sourceUrl',
          'issuing_authority' => 'issuingAuthority',
          'legal_instruments' => { '@id' => 'legalInstrument', '@container' => '@set' },
          'announcements' => { '@id' => 'announcement', '@container' => '@set' }
        }
      end
    end
  end
end
