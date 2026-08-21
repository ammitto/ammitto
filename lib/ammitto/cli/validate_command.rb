# frozen_string_literal: true

require 'thor'
require_relative '../data/china'

module Ammitto
  module Cmd
    # ValidateCommand provides validation CLI for sanctions data
    #
    # Supports validating YAML files against JSON schemas for various
    # country-specific data formats.
    #
    # @example Validate China data
    #   Ammitto::Cmd::ValidateCommand.start(['china', 'sources/'])
    #
    class ValidateCommand < Thor
      desc 'china [PATH]', 'Validate China YAML files against schemas'
      long_desc <<~DESC
        Validate China sanctions data YAML files against JSON schemas.

        If PATH is a file, validates that single file.
        If PATH is a directory, validates all YAML files in that directory.
        If no PATH is provided, validates all files in the default sources directory.

        Examples:
          ammitto validate china                          # Validate all in sources/
          ammitto validate china sources/sanction-lists/  # Validate specific directory
          ammitto validate china sources/sanction-lists/announcement.yml  # Single file
          ammitto validate china --verbose               # Show all file details
      DESC
      option :verbose, type: :boolean, default: false, aliases: '-v',
                       desc: 'Show detailed output for all files'
      option :sources, type: :string, default: 'sources', aliases: '-s',
                       desc: 'Default sources directory (used if PATH not provided)'
      def china(path = nil)
        validator = Ammitto::Data::China::Validator.new

        report = if path && File.file?(path)
                   validator.validate_files([path])
                 else
                   sources_dir = path || options[:sources]
                   validator.validate_all(sources_dir)
                 end

        print_report(report, options[:verbose])

        exit(report[:valid] ? 0 : 1)
      rescue ArgumentError => e
        warn "Error: #{e.message}"
        exit(2)
      rescue Ammitto::Data::China::SchemaNotFoundError => e
        warn "Schema error: #{e.message}"
        exit(2)
      end

      desc 'list [PATH]', 'List all YAML files and their detected schema types'
      long_desc <<~DESC
        List YAML files in a directory and show which schema type would be used
        for validation.

        Examples:
          ammitto validate list                     # List files in sources/
          ammitto validate list sources/            # List files in specific directory
      DESC
      option :sources, type: :string, default: 'sources', aliases: '-s',
                       desc: 'Path to sources directory'
      def list(path = nil)
        sources_dir = path || options[:sources]

        unless Dir.exist?(sources_dir)
          warn "Error: Sources directory not found: #{sources_dir}"
          exit(2)
        end

        validator = Ammitto::Data::China::Validator.new
        files = validator.find_yaml_files(sources_dir)

        if files.empty?
          puts "No YAML files found in #{sources_dir}"
        else
          puts "YAML files in #{sources_dir}:"
          files.each do |file|
            schema_type = Ammitto::Data::China::SchemaResolver.resolve(file)
            puts "  #{file} (#{schema_type})"
          end
          puts "\nTotal: #{files.length} files"
        end
      end

      desc 'schema [TYPE]', 'Show schema information'
      def schema(type = nil)
        case type
        when 'announcement', nil
          puts 'Announcement Schema: cn-announcement.yml'
          puts 'Used for standard sanction announcements with sanction_details'
        when 'modification'
          puts 'Modification Schema: cn-measure-modification.yml'
          puts 'Used for temporal modifications (suspend/continue/stop) with measure_modifications'
        when 'legal_instrument'
          puts 'Legal Instrument Schema: cn-legal-instrument.yml'
          puts 'Used for legal instruments and laws'
        when 'document_types'
          puts 'Document Types Schema: document-types.yml'
          puts 'Used for document type definitions'
        when 'organizations'
          puts 'Organizations Schema: organizations.yml'
          puts 'Used for organization definitions'
        else
          puts "Unknown schema type: #{type}"
          puts 'Available types: announcement, modification, legal_instrument, document_types, organizations'
          exit(1)
        end
      end

      # Ensure Thor exits with proper status code on failure
      def self.exit_on_failure?
        true
      end

      private

      # Print validation report
      # @param report [Hash] Validation report
      # @param verbose [Boolean] Whether to show verbose output
      def print_report(report, verbose)
        puts "\n=== Validation Report ==="
        puts "Total files: #{report[:total_files]}"
        puts "Valid files: #{report[:valid_files]}"
        puts "Invalid files: #{report[:invalid_files]}"

        if report[:valid]
          puts "\n✓ All files valid!"
        else
          puts "\n✗ Validation failed!"

          if verbose
            puts "\n=== Errors ==="
            report[:errors].each do |error_info|
              puts "\n#{error_info[:file]}:"
              error_info[:errors].each do |error|
                puts "  - #{error[:message]}"
              end
            end
          else
            puts "\nRun with --verbose to see detailed errors"
          end
        end
      end
    end
  end
end
