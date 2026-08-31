# frozen_string_literal: true

require 'thor'
require 'fileutils'
require 'tmpdir'
require 'yaml'

# The Japan arm refuses through Ammitto::ParseError. Declared here so this
# file stays independently loadable rather than relying on `ammitto.rb`
# having been required first.
require_relative '../errors/base_error'

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
      # @return [String] refusal when the spreadsheet parses to nothing
      EMPTY_METI_LIST = 'jp_meti: the Foreign User List parsed to zero ' \
                        'entities. METI has never published an empty ' \
                        'list, so this means the spreadsheet layout ' \
                        'moved and the parser silently matched nothing; ' \
                        'refusing rather than writing an empty file.'

      # Exit nonzero on command failure. Without it Thor exits 0, so
      # `ammitto source japan fetch meti` reported success while printing
      # `Could not find command "japan"` and doing nothing at all.

      def self.exit_on_failure?
        true
      end

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
        list = japan_meti_list(output_dir)
        # Bound to a local because `list` is a ForeignUserList, not an
        # Enumerable: `count` is a method it defines, and the collection
        # predicates RuboCop offers in its place do not exist on it.
        entities = list.count
        raise Ammitto::ParseError, EMPTY_METI_LIST if entities.zero?

        path = write_japan_meti_yaml(list, output_dir)
        puts "Fetched #{entities} #{entities == 1 ? 'entity' : 'entities'} to #{path}"
      end

      # The spreadsheet IS the source, so it always has to land on disk to
      # be parsed; `--no-save-xlsx` decides whether it survives the run.
      # It gets a directory of its own, removed with the block — passing
      # the extractor a nil `output_dir` would only move the file to the
      # shared `Dir.tmpdir` under whatever name METI served, where it
      # outlives the run and the next run collides with it.
      #
      # @param output_dir [String] where a kept spreadsheet is written
      # @return [Ammitto::Data::Japan::Meti::ForeignUserList]
      def japan_meti_list(output_dir)
        return meti_extractor(output_dir).fetch if options[:save_xlsx]

        Dir.mktmpdir { |scratch| meti_extractor(scratch).fetch }
      end

      # The module is `Meti`, not `METI`; this call named the latter and
      # raised NameError on every invocation that got far enough to reach
      # it.
      #
      # @param output_dir [String] directory the download is written to
      # @return [Ammitto::Data::Japan::Meti::Extractor]
      def meti_extractor(output_dir)
        Ammitto::Data::Japan::Meti::Extractor.new(
          output_dir: output_dir, verbose: options[:verbose]
        )
      end

      # One file for the whole list, which is what `ForeignUserList#to_hash`
      # is documented to produce. Per-entity files would imply this feeds
      # `harmonize`, and it does not: the published `jp` aggregate is built
      # from `data-jp/sources/sanction-lists/`, not from anything this
      # command writes.
      #
      # @param list [Ammitto::Data::Japan::Meti::ForeignUserList] parsed list
      # @param output_dir [String] directory to write into
      # @return [String] the path written
      def write_japan_meti_yaml(list, output_dir)
        FileUtils.mkdir_p(output_dir)
        path = File.join(output_dir, 'foreign-user-list.yaml')
        File.write(path, list.to_hash.to_yaml)
        path
      end

      def default_output_dir(subpath)
        File.join(Dir.pwd, 'data', subpath)
      end
    end
  end
end
