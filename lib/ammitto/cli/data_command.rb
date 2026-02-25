# frozen_string_literal: true

require 'json'
require_relative '../data/repository'

module Ammitto
  module Cmd
    # DataCommand manages the local data repository
    #
    # Subcommands:
    #   clone  - Clone the data repository to local storage
    #   pull   - Pull latest updates from remote
    #   status - Show repository status
    #   query  - Query entities from the data
    #   get    - Get an entity by ID
    #   sources - List available sources
    #   stats  - Show data statistics
    #
    class DataCommand
      # @return [Hash] command options
      attr_reader :options

      # @return [String] subcommand
      attr_reader :subcommand

      # @return [Array<String>] subcommand arguments
      attr_reader :args

      # Initialize with options and subcommand
      # @param options [Hash] command options
      # @param subcommand [String] subcommand name
      # @param args [Array<String>] subcommand arguments
      def initialize(options, subcommand = nil, *args)
        @options = options
        @subcommand = subcommand
        @args = args
      end

      # Execute the command
      # @return [void]
      def run
        case subcommand
        when 'clone'
          run_clone
        when 'pull'
          run_pull
        when 'status'
          run_status
        when 'query'
          run_query
        when 'get'
          run_get
        when 'sources'
          run_sources
        when 'stats'
          run_stats
        else
          puts "Unknown subcommand: #{subcommand}"
          puts "Available: clone, pull, status, query, get, sources, stats"
        end
      end

      private

      # Get the repository instance
      # @return [Ammitto::Data::Repository]
      def repo
        @repo ||= Ammitto::Data::Repository.new(
          local_path: options[:data_repository],
          verbose: options[:verbose]
        )
      end

      # Clone the repository
      def run_clone
        force = options[:force] || false
        puts "Cloning data repository..."
        puts "Local path: #{repo.local_path}"
        puts "Remote: #{repo.remote_url}"

        repo.clone(force: force)
        puts "Clone complete!"
        puts "Use 'ammitto data sources' to list available sources"
      end

      # Pull updates
      def run_pull
        unless repo.cloned?
          puts "Repository not cloned. Run 'ammitto data clone' first."
          return
        end

        puts "Pulling updates..."
        repo.pull
        puts "Pull complete!"
      end

      # Show repository status
      def run_status
        puts "Data Repository Status"
        puts "=" * 40
        puts "Local path: #{repo.local_path}"
        puts "Remote URL: #{repo.remote_url}"
        puts "Cloned: #{repo.cloned? ? 'Yes' : 'No'}"

        if repo.cloned?
          stats = repo.stats
          puts "\nStatistics:"
          puts "  Total entities: #{stats['total_entities'] || 'N/A'}"
          puts "  Sources: #{stats['sources']&.keys&.length || 0}"
          puts "  Generated at: #{stats['generated_at'] || 'N/A'}"
        end
      end

      # Query entities
      def run_query
        unless repo.cloned?
          puts "Repository not cloned. Run 'ammitto data clone' first."
          return
        end

        criteria = {}
        criteria[:name] = options[:name] if options[:name]
        criteria[:source] = options[:source] if options[:source]
        criteria[:type] = options[:type] if options[:type]
        criteria[:country] = options[:country] if options[:country]
        criteria[:limit] = options[:limit] if options[:limit]
        criteria[:offset] = options[:offset] if options[:offset]

        puts "Querying entities..." if options[:verbose]
        entities = repo.query(criteria)

        puts "Found #{entities.length} entities:"
        puts

        entities.each do |entity|
          print_entity(entity)
          puts "-" * 40
        end
      end

      # Get an entity by ID
      def run_get
        unless repo.cloned?
          puts "Repository not cloned. Run 'ammitto data clone' first."
          return
        end

        id = args.first
        unless id
          puts "Usage: ammitto data get <entity_id>"
          return
        end

        entity = repo.get(id)

        if entity
          puts "Entity: #{id}"
          puts "=" * 40
          puts JSON.pretty_generate(entity)
        else
          puts "Entity not found: #{id}"
        end
      end

      # List available sources
      def run_sources
        unless repo.cloned?
          puts "Repository not cloned. Run 'ammitto data clone' first."
          return
        end

        sources = repo.sources
        stats = repo.stats

        puts "Available Sources:"
        puts "=" * 40
        sources.sort.each do |source|
          count = stats.dig('sources', source, 'entities') || 'N/A'
          puts "  #{source.ljust(15)} #{count.to_s.rjust(6)} entities"
        end
        puts
        puts "Total: #{sources.length} sources"
      end

      # Show data statistics
      def run_stats
        unless repo.cloned?
          puts "Repository not cloned. Run 'ammitto data clone' first."
          return
        end

        stats = repo.stats

        puts "Data Statistics"
        puts "=" * 40
        puts "Generated at: #{stats['generated_at'] || 'N/A'}"
        puts "Total entities: #{stats['total_entities'] || 0}"
        puts
        puts "By Source:"

        stats['sources']&.each do |source, data|
          puts "  #{source.ljust(15)} #{data['entities'].to_s.rjust(6)} entities"
        end
      end

      # Print an entity summary
      # @param entity [Hash] Entity data
      def print_entity(entity)
        puts "ID: #{entity['id']}"
        puts "Type: #{entity['entity_type']}"

        primary_name = (entity['names'] || []).find { |n| n['is_primary'] }
        puts "Name: #{primary_name&.dig('full_name') || 'N/A'}"

        if entity['addresses']&.any?
          addr = entity['addresses'].first
          puts "Country: #{addr['country'] || 'N/A'}"
        end
      end
    end
  end
end
