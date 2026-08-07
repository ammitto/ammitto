# frozen_string_literal: true

require 'English'
require 'fileutils'
require_relative '../config/defaults'

module Ammitto
  module Cmd
    # Fetch command - download raw data from sources
    #
    # Downloads sanction data from specified sources and saves to YAML or JSON-LD.
    #
    # @example Fetch UK data as YAML
    #   ammitto fetch uk --format yaml --output-dir ./processed
    #
    # @example Fetch all automatable sources (skips manually managed cn)
    #   ammitto fetch --all
    #
    class FetchCommand
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

        # CN has no automated fetch: its YAML is manually managed in data-cn
        # (announcement-based reference docs). Reporting this explicitly beats
        # the extractor path returning success without writing anything.
        return error_result(source, 'CN data is manually managed in data-cn; automated fetch is not supported') if source == :cn

        # RU has no automated fetch either: mid.ru answers every request with
        # an F5/TSPD JavaScript anti-bot challenge shell (HTTP 200, zero
        # content links), so the Mechanize scraper structurally cannot see
        # the announcements. Refusing here beats a scrape that "succeeds"
        # with zero entities. Verified against the live site on 2026-08-06.
        if source == :ru
          return error_result(source,
                              'RU fetching is blocked: mid.ru serves a JavaScript ' \
                              'anti-bot challenge the scraper cannot pass, so automated ' \
                              'fetch does not work; refusing rather than reporting an ' \
                              'empty scrape as success')
        end

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
          extractor.run
        end
      rescue StandardError => e
        puts "[#{source}] ERROR: #{e.message}" if options[:verbose]
        puts e.backtrace.first(5).join("\n") if options[:verbose]
        error_result(source, e.message)
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
               when :jp
                 # JP is PDF-based - requires manual conversion
                 puts "[#{source}] Note: #{source.upcase} data is PDF-based"
                 puts "[#{source}] Data requires manual conversion from PDF"
                 model_class.from_pdf(content)
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
      # @raise [RuntimeError] when two different records claim one filename
      def save_as_yaml(source, data, output_dir)
        # Get the collection of designations/entities
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

      # Write each item to its own file, refusing to overwrite one record
      # with a different one.
      #
      # File.write truncates, so two items whose filenames collide used to
      # leave one record on disk and no trace of the other — the run still
      # reported success and the missing designee surfaced nowhere. A
      # repeated filename carrying byte-identical content is a duplicated
      # upstream row and collapses harmlessly; a repeated filename
      # carrying different content is data loss and fails the source.
      #
      # Collisions are resolved before anything is written, so a run that
      # would have discarded a record leaves the destination untouched
      # rather than half-replaced. Only filenames claimed more than once
      # are rendered twice, so the common path costs one pass.
      #
      # @param source [Symbol] source code
      # @param items [Array] items to write
      # @param output_dir [String] output directory
      # @return [Hash{String => Array}] filename => claimants
      # @raise [RuntimeError] when two different records claim one filename
      def write_items(source, items, output_dir)
        claims = items.group_by { |item| filename_for_item(source, item) }
        collisions = detect_collisions(claims)

        raise collision_error(source, collisions) unless collisions.empty?

        claims.each_with_index do |(filename, claimants), index|
          File.write(File.join(output_dir, filename),
                     claimants.first.to_yaml)
          report_progress(source, index + 1)
        end

        claims
      end

      # Find filenames claimed by records that are not byte-identical.
      #
      # A repeated filename carrying identical content is a duplicated
      # upstream row: writing it once loses nothing. Differing content is
      # data loss, because File.write truncates.
      #
      # @param claims [Hash{String => Array}] filename => claimants
      # @return [Hash{String => Array}] filename => records that would be
      #   discarded
      def detect_collisions(claims)
        require 'digest'

        claims.each_with_object({}) do |(filename, claimants), found|
          next if claimants.size == 1

          distinct = claimants.uniq do |item|
            Digest::SHA256.hexdigest(item.to_yaml)
          end
          next if distinct.size == 1

          found[filename] = distinct.drop(1)
        end
      end

      # Report progress every hundredth file actually written
      # @param source [Symbol] source code
      # @param count [Integer] files written so far
      # @return [void]
      def report_progress(source, count)
        return unless options[:verbose] && (count % 100).zero?

        puts "[#{source}] Saved #{count} files..."
      end

      # @param source [Symbol] source code
      # @param collisions [Hash{String => Array}] filename => lost items
      # @return [String] message naming every discarded record
      def collision_error(source, collisions)
        detail = collisions.map do |filename, items|
          labels = items.map { |item| describe_item(item) }.join(', ')
          "#{filename} (also claimed by #{labels})"
        end.join('; ')

        "#{source}: #{collisions.size} filename collision(s) would " \
          "discard #{collisions.values.sum(&:size)} record(s): #{detail}"
      end

      # Best-effort label for a record in an error message.
      #
      # A diagnostic must never mask the error it describes, so a record
      # whose own accessors raise, or whose name is unbounded, degrades to
      # a shorter label instead of escaping as an unrelated exception.
      #
      # @param item [Object] the item
      # @return [String]
      def describe_item(item)
        %i[name full_name vessel_name english_name].each do |attr|
          value = begin
            item.respond_to?(attr) ? item.public_send(attr).to_s.strip : ''
          rescue StandardError
            ''
          end

          return "#{value[0, 80].inspect}..." if value.length > 80
          return value.inspect unless value.empty?
        end

        begin
          item.class.name.to_s
        rescue StandardError
          '(unprintable record)'
        end
      end

      # Get items collection from parsed data
      # @param source [Symbol] source code
      # @param data [Object] parsed data
      # @return [Array] collection of items
      def items_from_data(source, data)
        case source
        when :uk
          data.designations || []
        when :eu
          data.sanction_entities || []
        when :un
          (data.all_individuals || []) + (data.all_entities || [])
        when :us
          data.entries || []
        when :wb
          data.firms || []
        when :au
          (data.individuals || []) + (data.organizations || []) + (data.vessels || [])
        when :ca
          data.records || []
        when :ch
          data.all_identities || []
        when :cn
          data.all_entities || data.entities || []
        when :ru
          data.all_entities || data.entities || []
        when :tr
          data.entities || []
        when :nz
          (data.individuals || []) + (data.entities || []) + (data.ships || [])
        when :eu_vessels
          data.vessels || []
        when :jp
          data.entities || []
        when :un_vessels
          data.vessels || []
        else
          []
        end
      end

      # Generate filename for an item
      # @param source [Symbol] source code
      # @param item [Object] the item
      # @return [String] filename
      def filename_for_item(source, item)
        case source
        when :uk
          ref = item.unique_id || "unknown-#{item.object_id}"
          "#{ref.downcase.gsub(/[^a-z0-9]/, '-')}.yaml"
        when :eu
          ref = item.eu_reference_number || "unknown-#{item.object_id}"
          "#{ref.downcase.gsub(/[^a-z0-9]/, '-')}.yaml"
        when :un
          ref = item.reference_number || "unknown-#{item.object_id}"
          "#{ref.downcase.gsub(/[^a-z0-9]/, '-')}.yaml"
        when :us
          ref = item.uid || "unknown-#{item.object_id}"
          "#{ref.downcase.gsub(/[^a-z0-9]/, '-')}.yaml"
        when :wb
          ref = item.supp_id || "unknown-#{item.object_id}"
          "wb-#{ref}.yaml"
        when :au
          ref = item.reference || item.id || "unknown-#{item.object_id}"
          "au-#{ref}.yaml"
        when :ca
          ref = item.generate_id || item.item || "unknown-#{item.object_id}"
          "ca-#{ref}.yaml"
        when :ch
          ref = item.ssid || item.full_name&.gsub(/\s+/, '-') || "unknown-#{item.object_id}"
          "ch-#{ref}.yaml"
        when :cn
          ref = item.english_name || item.chinese_name || "unknown-#{item.object_id}"
          "cn-#{ref.to_s.downcase.gsub(/[^a-z0-9]/, '-')}.yaml"
        when :ru
          ref = item.english_name || item.russian_name || "unknown-#{item.object_id}"
          "ru-#{ref.to_s.downcase.gsub(/[^a-z0-9]/, '-')}.yaml"
        when :tr
          # local_id, not reference_number: Turkey assigns one "Sıra No"
          # to two organisations, and local_id is what tells them apart.
          # Harmonize mints IRIs from the same method, so a record that
          # gets its own file here also gets its own graph node.
          ref = item.local_id || item.name || "unknown-#{item.object_id}"
          "tr-#{ref.to_s.downcase.gsub(/[^a-z0-9]/, '-')}.yaml"
        when :nz
          ref = item.unique_identifier || item.reference_number || "unknown-#{item.object_id}"
          "nz-#{ref.to_s.downcase.gsub(/[^a-z0-9]/, '-')}.yaml"
        when :eu_vessels
          ref = item.imo_number || item.unique_identifier || "unknown-#{item.object_id}"
          "eu-vessel-#{ref}.yaml"
        when :jp
          ref = item.id || item.unique_identifier || "unknown-#{item.object_id}"
          "jp-#{ref}.yaml"
        when :un_vessels
          # local_id, not unique_identifier: the fallback identity for
          # the one vessel listed without an IMO number must be its
          # name slug, which is stable across harvests — the previous
          # unique_identifier fallback stringified a nil IMO into the
          # constant ref "IMO-".
          ref = item.local_id || "unknown-#{item.object_id}"
          "un-vessel-#{ref}.yaml"
        else
          "#{item.object_id}.yaml"
        end
      end

      # Get source model class for a source
      # @param source [Symbol] source code
      # @return [Class, nil] the source model class
      def source_model_class_for(source)
        case source
        when :uk
          require_relative '../sources/uk'
          Ammitto::Sources::Uk::Designations
        when :eu
          require_relative '../sources/eu'
          Ammitto::Sources::Eu::Export
        when :un
          require_relative '../sources/un'
          Ammitto::Sources::Un::ConsolidatedList
        when :us
          require_relative '../sources/us'
          Ammitto::Sources::Us::SdnList
        when :wb
          require_relative '../sources/wb'
          Ammitto::Sources::Wb::Response
        when :au
          require_relative '../sources/au'
          Ammitto::Sources::Au::SanctionsList
        when :ca
          require_relative '../sources/ca'
          Ammitto::Sources::Ca::SanctionsList
        when :ch
          require_relative '../sources/ch'
          Ammitto::Sources::Ch::SanctionsList
        when :tr
          require_relative '../sources/tr'
          Ammitto::Sources::Tr::SanctionsList
        when :nz
          require_relative '../sources/nz'
          Ammitto::Sources::Nz::SanctionsList
        when :eu_vessels
          require_relative '../sources/eu_vessels'
          Ammitto::Sources::EuVessels::SanctionsList
        when :jp
          require_relative '../sources/jp'
          Ammitto::Sources::Jp::SanctionsList
        when :un_vessels
          require_relative '../sources/un_vessels'
          Ammitto::Sources::UnVessels::SanctionsList
        end
      rescue LoadError
        nil
      end

      # Get extractor class for source
      # @param source [Symbol] source code
      # @return [Class, nil] extractor class
      def extractor_class_for(source)
        # Load extractors lazily
        require_relative '../extractors/registry'

        Ammitto::Extractors::Registry.get(source)
      rescue LoadError
        nil
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
