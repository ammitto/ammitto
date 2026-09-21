# frozen_string_literal: true

require 'English'
require 'fileutils'
require 'yaml'
require_relative '../config/defaults'
require_relative '../errors/base_error'
require_relative 'fetch/source_registry'
require_relative 'fetch/item_mapper'
require_relative 'fetch/collision_and_collapse_guard'

module Ammitto
  module Cmd
    # Fetch command - download raw data from sources
    #
    # Downloads sanction data from specified sources and saves to YAML or JSON-LD.
    #
    # @example Fetch UK data as YAML
    #   ammitto fetch uk --format yaml --output-dir ./processed
    #
    # @example Fetch every source with a working fetch path (skips cn,
    #   ru and jp, none of which this command can reach)
    #   ammitto fetch --all
    #
    class FetchCommand
      include Fetch::SourceRegistry
      include Fetch::ItemMapper
      include Fetch::CollisionAndCollapseGuard

      COLLAPSE_RATIO = Fetch::CollisionAndCollapseGuard::COLLAPSE_RATIO
      NO_FETCH_PATH = Fetch::SourceRegistry::NO_FETCH_PATH

      # @return [Hash] command options
      attr_reader :options

      # @return [Array<Symbol>] sources to fetch
      attr_reader :sources

      # Initialize with options and sources
      # @param options [Hash] command options
      # @param sources [Array<String>] source codes
      def initialize(options, sources)
        @options = options
        @sources = normalize_sources(sources)
      end

      # Execute the command
      # @return [void]
      def run
        validate_sources!

        if options[:dry_run]
          dry_run
        else
          fetch_all
        end
      end

      private

      # Normalize source codes to symbols
      # @param sources [Array<String>]
      # @return [Array<Symbol>]
      def normalize_sources(sources)
        return Config::Defaults::FETCHABLE_SOURCES if options[:all]

        if sources.empty?
          raise Thor::Error,
                'No sources specified. Pass source codes (e.g. `ammitto fetch uk eu`) or use --all.'
        end

        sources.map(&:to_s).map(&:downcase).map(&:to_sym)
      end

      # Validate source codes
      # @raise [ArgumentError] if invalid source
      def validate_sources!
        invalid = @sources - Config::Defaults::ALL_SOURCES
        return if invalid.empty?

        raise Thor::Error,
              "Invalid sources: #{invalid.join(', ')}. " \
              "Valid: #{Config::Defaults::ALL_SOURCES.join(', ')}"
      end

      # Show what would be done (dry run)
      # @return [void]
      def dry_run
        puts 'Would fetch data from:'
        @sources.each do |source|
          # A source with no fetch path must not advertise an endpoint.
          # These sources still have an extractor class, so asking it for
          # an api_endpoint prints a URL and implies a fetch that
          # `fetch #{source}` then refuses — and --dry-run is the path a
          # user checks first, so it is the one that must not mislead.
          if (no_path = NO_FETCH_PATH[source])
            puts "  #{source}: #{no_path}"
            next
          end

          extractor_class = extractor_class_for(source)
          endpoint = extractor_class&.new&.api_endpoint
          puts "  #{source}: #{endpoint || 'N/A'}"
        end
      end

      # Fetch all requested sources
      # @return [void]
      def fetch_all
        results = @sources.map do |source|
          fetch_source(source)
        end

        print_summary(results)
        enforce_exit_status(results)
      end

      # Fetch a single source
      # @param source [Symbol] source code
      # @return [Hash] fetch result
      def fetch_source(source)
        puts "[#{source}] Fetching..." if options[:verbose]

        no_path = NO_FETCH_PATH[source]
        return error_result(source, no_path) if no_path

        extractor_class = extractor_class_for(source)
        return error_result(source, 'No extractor available') unless extractor_class

        # Create output directory
        output_dir = options[:output_dir] || File.join(cache_dir, 'processed', source.to_s)
        FileUtils.mkdir_p(output_dir)

        # Create extractor instance
        extractor = extractor_class.new
        extractor.verbose = options[:verbose] if extractor.respond_to?(:verbose=)

        # Fetch and parse using source models if format is yaml
        format = options[:format] || 'yaml'

        if format == 'yaml' && source_model_class_for(source)
          fetch_with_source_models(source, extractor, output_dir)
        else
          # The same refusal has to cover this branch. BaseExtractor#run
          # reports :success with entities: 0 when the parse yielded
          # nothing, and `--format jsonld` is a documented value, so
          # guarding only the yaml path would leave the lie reachable
          # through a supported flag.
          refuse_empty_extraction(source, extractor.run)
        end
      rescue StandardError => e
        puts "[#{source}] ERROR: #{e.message}" if options[:verbose]
        puts e.backtrace.first(5).join("\n") if options[:verbose]
        error_result(source, e.message)
      end

      # Turn an extractor run that parsed to nothing into an error.
      #
      # @param source [Symbol] source code
      # @param result [Hash] the extractor's own result
      # @return [Hash] the result, or an error result when it found nothing
      def refuse_empty_extraction(source, result)
        return result unless result[:status] == :success
        return result unless result[:entities].to_i.zero? &&
                             result[:entries].to_i.zero?

        error_result(
          source,
          "extracted 0 records: #{source} returned a document that " \
          'parsed to nothing. The source format has probably changed; ' \
          'refusing to report success.'
        )
      end

      # Fetch data using Lutaml::Model source models
      # @param source [Symbol] source code
      # @param extractor [BaseExtractor] the extractor
      # @param output_dir [String] output directory
      # @return [Hash] fetch result
      def fetch_with_source_models(source, extractor, output_dir)
        puts "[#{source}] Fetching with source models..." if options[:verbose]

        # Fetch raw content using extractor's fetch method (handles tokens, etc.)
        puts "[#{source}] Downloading from #{extractor.api_endpoint}" if options[:verbose]
        content = extractor.fetch

        # Parse using source model
        model_class = source_model_class_for(source)
        raise "No source model for #{source}" unless model_class

        puts "[#{source}] Parsing with #{model_class.name}..." if options[:verbose]

        # Detect format and parse accordingly
        data = case source
               when :wb
                 require 'json'
                 # WB model's from_json expects the raw JSON string
                 model_class.from_json(content)
               when :au, :tr, :nz, :eu_vessels
                 # AU, TR, NZ, EU Vessels use XLSX - content is path to temp file
                 parse_xlsx(model_class, content, extractor)
               when :un_vessels
                 # UN Vessels parses the downloaded PDF directly -
                 # content is the path to the extractor's temp file
                 parse_pdf(model_class, content, extractor)
               else
                 # XML sources - content is already a string from extractor
                 model_class.from_xml(content)
               end

        # Save as individual YAML files
        count = save_as_yaml(source, data, output_dir)

        # A harvest that wrote nothing is a failure, not a quiet success.
        # `count` was recorded and never consulted: enforce_exit_status
        # selects on :error only, so a source whose document parsed to
        # nothing — a changed namespace, a maintenance page served with a
        # 200, a renamed root element — reported "1 succeeded, 0 failed"
        # and exited 0. Nothing deletes the previous harvest either, so
        # the downstream harmonize gate then passed on yesterday's files
        # and stayed green too.
        #
        # These are sanctions lists. RuExtractor already states the
        # principle for its own source: the stop-list is never
        # legitimately empty. This applies it to every source that has a
        # fetch path.
        if count.zero?
          return {
            code: source,
            status: :error,
            error: "wrote 0 records: #{source} returned a document that " \
                   'parsed to nothing. The source format has probably ' \
                   'changed; refusing to report success.',
            output_dir: output_dir
          }
        end

        {
          code: source,
          status: :success,
          count: count,
          output_dir: output_dir
        }
      end

      # Save data as individual YAML files
      # @param source [Symbol] source code
      # @param data [Object] the parsed data
      # @param output_dir [String] output directory
      # @return [Integer] number of files saved
      # @raise [Ammitto::Cmd::Fetch::FilenameCollisionError] when two
      #   different records claim one filename
      # @raise [Ammitto::ParseError] raised through by write_items
      def save_as_yaml(source, data, output_dir)
        items = items_from_data(source, data)
        written = write_items(source, items, output_dir)

        # Save index file with metadata. count is the number of files
        # this run wrote, not the number of items it saw: they used to
        # differ silently whenever two items shared a filename, so the run
        # reported more records than it had actually written.
        #
        # Not a count of the directory's contents. Nothing here removes
        # files from a previous harvest, so a delisted record's file
        # outlives the run that dropped it — longstanding behaviour of
        # this command, and a separate question from whether one run
        # overwrites its own records.
        count = written.size
        index = {
          'source' => source.to_s,
          'count' => count,
          'fetched_at' => Time.now.utc.iso8601,
          'schema' => "ammitto:sources:#{source}:v1"
        }
        File.write(File.join(output_dir, '_index.yaml'), index.to_yaml)

        puts "[#{source}] Saved #{count} files to #{output_dir}" if options[:verbose]

        count
      end

      # Parse a workbook and dispose of the temporary file it arrived in.
      #
      # The download is a Tempfile, and a parse that refuses the payload
      # is a normal outcome on these sources, not a crash — so disposal
      # has to happen whether the parse returned or raised. It used to
      # happen only on the returning path, which leaked the workbook of
      # every refused harvest.
      #
      # A bare +ensure+ that let a disposal failure escape would fix the
      # leak and introduce a worse problem: if unlinking fails while an
      # integrity failure is in flight, Ruby replaces the exception, and
      # the operator is told about a temp file instead of why the
      # harvest was refused. So disposal runs unconditionally, and only
      # speaks when it has nothing to interrupt.
      #
      # +ensure+ rather than +rescue StandardError+ because Interrupt is
      # not a StandardError: cancelling a long parse with Ctrl-C took
      # the only other exit out of the method and leaked the workbook it
      # had already downloaded.
      #
      # @param model_class [Class] source model to parse with
      # @param content [String] path to the downloaded workbook
      # @param extractor [Object] extractor owning the temporary file
      # @return [Object] the parsed model
      def parse_xlsx(model_class, content, extractor)
        model_class.from_xlsx(content)
      ensure
        # $! is the exception on its way out, if any. Captured before
        # disposal so a failure here is measured against the reason the
        # parse ended, not against itself.
        interrupted = $ERROR_INFO
        begin
          cleanup_extractor(extractor)
        rescue StandardError => e
          raise unless interrupted

          warn "[cleanup] #{e.message}"
        end
      end

      # PDF twin of parse_xlsx: same disposal contract, for the same
      # reason — the download is a Tempfile, and a parse that refuses
      # the payload must not leak it.
      #
      # @param model_class [Class] source model to parse with
      # @param content [String] path to the downloaded PDF
      # @param extractor [Object] extractor owning the temporary file
      # @return [Object] the parsed model
      def parse_pdf(model_class, content, extractor)
        model_class.from_pdf(content)
      ensure
        interrupted = $ERROR_INFO
        begin
          cleanup_extractor(extractor)
        rescue StandardError => e
          raise unless interrupted

          warn "[cleanup] #{e.message}"
        end
      end

      # @param extractor [Object] extractor owning the temporary file
      # @return [void]
      def cleanup_extractor(extractor)
        extractor.cleanup if extractor.respond_to?(:cleanup)
      end

      # Get cache directory
      # @return [String]
      def cache_dir
        options[:cache_dir] || File.expand_path('~/.ammitto')
      end

      # Create error result hash
      # @param source [Symbol] source code
      # @param message [String] error message
      # @return [Hash]
      def error_result(source, message)
        {
          code: source,
          status: :error,
          error: message
        }
      end

      # Print summary of results
      # @param results [Array<Hash>] fetch results
      # @return [void]
      def print_summary(results)
        success = results.count { |r| r[:status] == :success }
        failed = results.count { |r| r[:status] == :error }

        puts
        puts "Fetch complete: #{success} succeeded, #{failed} failed"

        return unless failed.positive?

        puts 'Failed sources:'
        results.select { |r| r[:status] == :error }.each do |r|
          puts "  #{r[:code]}: #{r[:error]}"
        end
      end

      # A run with any failed source must exit nonzero: otherwise cron/CI
      # logs the per-source error and still concludes success, so a dead
      # source keeps its published data silently stale behind green runs.
      # @param results [Array<Hash>] fetch results
      # @return [void]
      # @raise [Thor::Error] when any requested source failed
      def enforce_exit_status(results)
        failed = results.select { |r| r[:status] == :error }
        return if failed.empty?

        raise Thor::Error,
              "Fetch failed for: #{failed.map { |r| r[:code] }.join(', ')}"
      end
    end
  end
end
