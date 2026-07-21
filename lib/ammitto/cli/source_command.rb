# frozen_string_literal: true

require 'thor'
require 'fileutils'
require 'yaml'

module Ammitto
  module Cmd
    # Source command - fetch data from specific country sources
    #
    # @example Fetch METI Foreign User List
    #   ammitto source japan fetch meti
    #
    # @example Fetch with output directory
    #   ammitto source japan fetch meti --output-dir ./data/japan/meti
    #
    class SourceCommand < Thor
      desc 'fetch COUNTRY SOURCE', 'Fetch data from a specific country and source'
      option :output_dir, type: :string, desc: 'Output directory for YAML files'
      option :save_xlsx, type: :boolean, default: true, desc: 'Save downloaded Excel file'
      option :verbose, type: :boolean, default: false, desc: 'Enable verbose output'

      def fetch(country, source)
        case country.downcase
        when 'japan'
          fetch_japan(source)
        when 'china', 'cn'
          fetch_china(source)
        else
          puts "Country '#{country}' not supported. Supported: japan, china"
          exit 1
        end
      end

      private

      def fetch_japan(source)
        case source.downcase
        when 'meti'
          fetch_japan_meti
        else
          puts "Source '#{source}' not supported for Japan. Supported: meti"
          exit 1
        end
      end

      def fetch_china(source)
        require_relative '../data/china'
        output_dir = options[:output_dir] || default_output_dir('china')

        unless Ammitto::Data::China::Extractor.valid_source?(source)
          puts "Source '#{source}' not supported for China."
          puts "Supported sources: #{Ammitto::Data::China::Extractor.available_sources.join(', ')}"
          exit 1
        end

        puts "Fetching China #{source}..." if options[:verbose]
        extractor = Ammitto::Data::China::Extractor.new(source, verbose: options[:verbose])
        count = extractor.fetch_to_yaml(output_dir)
        puts "Fetched #{count} items to #{output_dir}"
      end

      def fetch_japan_meti
        require_relative '../data/japan/meti/extractor'
        output_dir = options[:output_dir] || default_output_dir('japan/meti')

        puts 'Fetching METI Foreign User List...' if options[:verbose]
        extractor = Ammitto::Data::Japan::METI::Extractor.new(verbose: options[:verbose])
        count = extractor.fetch_to_yaml(output_dir)
        puts "Fetched #{count} items to #{output_dir}"
      end

      def default_output_dir(subpath)
        File.join(Dir.pwd, 'data', subpath)
      end
    end
  end
end
