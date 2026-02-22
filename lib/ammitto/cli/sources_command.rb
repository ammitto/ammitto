# frozen_string_literal: true

require_relative '../config/defaults'

module Ammitto
  module Cmd
    # Sources command - list available sanction sources
    #
    # Displays all available sanction sources with their properties.
    class SourcesCommand
      # @return [Hash] command options
      attr_reader :options

      # Initialize with options
      # @param options [Hash] command options
      def initialize(options)
        @options = options
      end

      # Execute the command
      # @return [void]
      def run
        if options[:format] == 'json'
          output_json
        else
          output_table
        end
      end

      private

      # Get sources data
      # @return [Array<Hash>]
      def sources_data
        [
          { code: 'eu', name: 'European Union', format: 'XML', machine_readable: true },
          { code: 'un', name: 'United Nations', format: 'XML', machine_readable: true },
          { code: 'us', name: 'United States (OFAC)', format: 'XML', machine_readable: true },
          { code: 'wb', name: 'World Bank', format: 'JSON', machine_readable: true },
          { code: 'uk', name: 'United Kingdom (OFSI)', format: 'XML', machine_readable: true },
          { code: 'au', name: 'Australia (DFAT)', format: 'CSV', machine_readable: true },
          { code: 'ca', name: 'Canada (SEFO)', format: 'XML', machine_readable: true },
          { code: 'ch', name: 'Switzerland (SECO)', format: 'XML', machine_readable: true },
          { code: 'cn', name: 'China (MOFCOM/MFA)', format: 'HTML', machine_readable: false },
          { code: 'ru', name: 'Russia (MID)', format: 'HTML', machine_readable: false }
        ]
      end

      # Output as table
      # @return [void]
      def output_table
        puts 'Available Sanction Sources:'
        puts
        puts format_row('Code', 'Authority', 'Format', 'Machine-readable')
        puts '-' * 60

        sources_data.each do |source|
          puts format_row(
            source[:code],
            source[:name],
            source[:format],
            source[:machine_readable] ? 'yes' : 'no'
          )
        end

        puts
        puts "Use 'ammitto fetch <code>' to download data from a source."
      end

      # Output as JSON
      # @return [void]
      def output_json
        require 'json'
        puts JSON.pretty_generate(sources_data)
      end

      # Format a table row
      # @return [String]
      def format_row(code, name, format, readable)
        format('%-6s %-30s %-8s %s', code, name, format, readable)
      end
    end
  end
end
