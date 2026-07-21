# frozen_string_literal: true

require 'json'

module Ammitto
  module Cmd
    # Get command - fetch a specific entity by ID
    #
    # @example
    #   ammitto get un/KPi.066              # Get by short path
    #   ammitto get eu/EU.10982.59          # Get EU entity
    #   ammitto get KPi.066 --format json   # Get by reference number
    #
    class GetCommand
      # @return [Hash] command options
      attr_reader :options

      # @return [String] entity ID
      attr_reader :id

      # Initialize with options and ID
      # @param options [Hash] command options
      # @param id [String] entity ID
      def initialize(options, id)
        @options = options
        @id = id.to_s.strip
      end

      # Execute the command
      # @return [void]
      def run
        if id.empty?
          puts 'Error: ID required. Usage: ammitto get ID'
          puts '  ammitto get un/KPi.066'
          puts '  ammitto get EU.10982.59'
          exit 1
        end

        repo = create_repository

        unless repo.cloned?
          puts "Data repository not found. Run 'ammitto data clone' first."
          puts 'Or set AMMITTO_DATA_REPOSITORY environment variable.'
          exit 1
        end

        entity = repo.get(id)

        if entity.nil?
          puts "Entity not found: #{id}"
          exit 1
        end

        output_entity(entity)
      end

      private

      # Create the data repository
      # @return [Ammitto::Data::Repository]
      def create_repository
        require_relative '../data/repository'
        local_path = options[:data_repository] || ENV.fetch('AMMITTO_DATA_REPOSITORY', nil)
        Ammitto::Data::Repository.new(
          local_path: local_path,
          verbose: options[:verbose]
        )
      end

      # Output entity data
      # @param entity [Hash] entity data
      def output_entity(entity)
        unless options[:format] == 'json'
          puts "Entity: #{id}"
          puts '=' * 60
        end
        puts JSON.pretty_generate(entity)
      end
    end
  end
end
