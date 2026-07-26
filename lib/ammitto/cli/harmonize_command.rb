# frozen_string_literal: true

require 'fileutils'
require 'yaml'
require 'json'
require_relative '../serialization/json_ld_graph_exporter'
require_relative '../serialization/search_index_exporter'
require_relative '../serialization/ontology_exporter'
require_relative '../serialization/json_ld_serializer'

module Ammitto
  module Cmd
    # Harmonize command - transform YAML source data to JSON-LD knowledge graph
    #
    # Reads YAML files from source directories, transforms them using
    # transformers, and exports as a JSON-LD knowledge graph with:
    # - Individual node files per entity, entry, instrument, regime, authority
    # - Aggregated all.jsonld and all.ttl files
    # - Index files for each node type
    class HarmonizeCommand
      # @return [Hash] command options
      attr_reader :options

      # @return [Array<Symbol>] sources to harmonize
      attr_reader :sources

      # @return [JsonLdGraphExporter] the graph exporter
      attr_reader :exporter

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
        allowed_empty_sources # fail fast on unknown --allow-empty codes

        raise Thor::Error, 'No sources to harmonize. Specify sources or use --all.' if @sources.empty?

        harmonize_all
      end

      private

      # Normalize source codes
      # @param sources [Array<String>]
      # @return [Array<Symbol>]
      def normalize_sources(sources)
        if options[:scan]
          # Auto-detect data-* repositories
          parent_dir = options[:sources_dir] || Config::Defaults::SOURCES_DIR
          detected = Config::Defaults.detect_data_repositories(parent_dir)
          puts "Auto-detected sources: #{detected.join(', ')}" if options[:verbose]
          detected
        elsif options[:all]
          Config::Defaults::ALL_SOURCES
        elsif sources.empty?
          []
        else
          sources.map(&:to_s).map(&:downcase).map(&:to_sym)
        end
      end

      # Validate source codes
      # @raise [ArgumentError] if invalid source
      def validate_sources!
        # Allow any detected source - validation is for explicitly provided sources
        return if options[:scan]

        # Check against known sources (hardcoded + potentially detected)
        known_sources = Config::Defaults::ALL_SOURCES
        invalid = @sources - known_sources
        return if invalid.empty?

        raise Thor::Error,
              "Invalid sources: #{invalid.join(', ')}. " \
              "Valid: #{known_sources.join(', ')}"
      end

      # Harmonize all sources
      # @return [void]
      def harmonize_all
        output_dir = options[:output_dir] || './api/v1'

        # Create exporters (--combine controls all.jsonld/all.ttl emission)
        @exporter = Serialization::JsonLdGraphExporter.new(
          output_dir: output_dir,
          combine: options[:combine] == true,
          instruments_dir: find_instruments_dir,
          supporting_dir: find_supporting_dir
        )
        @search_indexer = Serialization::SearchIndexExporter.new
        @ontology_exporter = Serialization::OntologyExporter.new

        results = @sources.map do |source|
          harmonize_source(source)
        end

        # Export all collected nodes to files
        if results.any? { |r| r[:status] == :success }
          puts 'Exporting knowledge graph...' if options[:verbose]
          @exporter.export

          puts 'Exporting search index...' if options[:verbose]
          @search_indexer.export(output_dir)

          puts 'Exporting ontology data...' if options[:verbose]
          @ontology_exporter.export(output_dir)
        end

        print_summary(results)
        enforce_health_gates(results)
      end

      # Health gates: a run that produced no data or swallowed errors must
      # exit nonzero so cron/CI cannot publish empty artifacts as success.
      # Strict by default; the caller opts individual sources out of the
      # source-error, zero-entity, and missing-aggregate checks with
      # --allow-empty (the raise-or-silence policy belongs to the invoking
      # workflow, not to a hardcoded list). Per-file transform errors are
      # never exempt: a file that exists but fails to transform is a data
      # defect regardless of the source's status.
      # @param results [Array<Hash>] per-source results
      # @return [void]
      def enforce_health_gates(results)
        allowed_empty = allowed_empty_sources
        failures = []

        output_dir = options[:output_dir] || './api/v1'

        results.each do |r|
          code = r[:code]
          # Per-file errors are checked first and are never exempt
          if r[:errors]&.any?
            failures << "#{code}: #{r[:errors].length} file(s) failed to transform " \
                        "(first: #{r[:errors].first})"
          elsif r[:status] == :error
            failures << "#{code}: #{r[:error]}" unless allowed_empty.include?(code)
          elsif r[:entities].to_i.zero? && !allowed_empty.include?(code)
            failures << "#{code}: produced 0 entities"
          elsif !allowed_empty.include?(code) &&
                !File.exist?(File.join(output_dir, 'sources', "#{code}.jsonld"))
            failures << "#{code}: per-source aggregate sources/#{code}.jsonld was not written"
          end
        end

        return if failures.empty?

        raise Thor::Error,
              "Harmonize health gate failed:\n  #{failures.join("\n  ")}"
      end

      # Sources the caller exempts from the source-error, zero-entity, and
      # missing-aggregate gates (--allow-empty). Per-file transform errors
      # are never exempt.
      # @return [Array<Symbol>] validated source codes
      def allowed_empty_sources
        @allowed_empty_sources ||= begin
          codes = options[:allow_empty].to_s.split(',').map { |c| c.strip.downcase.to_sym }.reject(&:empty?).uniq
          unknown = codes - Config::Defaults::ALL_SOURCES
          unless unknown.empty?
            raise Thor::Error,
                  "Unknown sources in --allow-empty: #{unknown.join(', ')}. " \
                  "Valid: #{Config::Defaults::ALL_SOURCES.join(', ')}"
          end
          codes
        end
      end

      # Write the per-source JSON-LD aggregate (sources/<code>.jsonld)
      # @param source [Symbol] source code
      # @param graph [Array<Hash>] entity and entry hashes
      # @return [void]
      def write_source_aggregate(source, graph)
        output_dir = options[:output_dir] || './api/v1'
        sources_dir = File.join(output_dir, 'sources')
        FileUtils.mkdir_p(sources_dir)

        # Dedupe by @id with last-wins semantics — the same winner rule the
        # global exporter uses (hash assignment), so per-source and global
        # artifacts agree on duplicate ids
        deduped = graph.to_h { |node| [node['@id'] || node.object_id, node] }.values

        document = {
          '@context' => Schema::Context.context_url,
          '@graph' => deduped
        }
        File.write(File.join(sources_dir, "#{source}.jsonld"), JSON.pretty_generate(document))
      end

      # Harmonize a single source
      # @param source [Symbol] source code
      # @return [Hash] harmonize result
      def harmonize_source(source)
        puts "[#{source}] Harmonizing..." if options[:verbose]

        input_dir, yaml_files = find_input_dir(source)
        unless input_dir
          puts "[#{source}] No input directory found. Run 'ammitto fetch' first." if options[:verbose]
          return { code: source, status: :error, error: 'No input directory found' }
        end

        return { code: source, status: :error, error: 'No YAML files found' } if yaml_files.empty?

        # Parse and transform
        entities_count = 0
        entries_count = 0
        errors = []
        source_graph = []

        yaml_files.each do |file|
          data = YAML.safe_load_file(file, permitted_classes: [Date, Time], aliases: true)
          next unless data

          begin
            result = transform_data(source, data)
            added = ingest_results(result, source, source_graph, errors, File.basename(file))
            entities_count += added
            entries_count += added
          rescue StandardError => e
            error_msg = "#{File.basename(file)}: #{e.message}"
            puts "[#{source}] Error processing #{error_msg}" if options[:verbose]
            errors << error_msg
          end
        end

        # Per-source aggregate: required by BaseSource downloads and
        # Data::Repository#load_source (artifact-topology contract)
        write_source_aggregate(source, source_graph) if entities_count.positive?

        puts "[#{source}] Harmonized #{entities_count} entities" if options[:verbose]

        result = { code: source, status: :success, entities: entities_count, entries: entries_count }
        result[:errors] = errors if errors.any?
        result
      rescue StandardError => e
        puts "[#{source}] ERROR: #{e.message}" if options[:verbose]
        { code: source, status: :error, error: e.message }
      end

      # Feed transformed results into the exporters. A source file may
      # transform into one result or an array of results (e.g. CN
      # announcements carrying multiple entities).
      # @param result [Hash, Array<Hash>] transform output
      # @param source [Symbol] source code
      # @param source_graph [Array<Hash>] per-source aggregate collector
      # @param errors [Array<String>] per-file error collector (health gates)
      # @param filename [String] source file for error attribution
      # @return [Integer] number of entity/entry pairs ingested
      def ingest_results(result, source, source_graph, errors, filename)
        results_list = result.is_a?(Array) ? result : [result]
        added = 0

        results_list.each do |r|
          # Both halves absent is a designed skip (e.g. CN measure
          # modifications); a non-Hash result or half-formed pair is a data
          # defect and must surface through the health gates.
          unless r.is_a?(Hash)
            errors << "#{filename}: transform produced invalid result (#{r.class})"
            next
          end
          next if r[:entity].nil? && r[:entry].nil?

          unless r[:entity]&.key?('@id') && r[:entry]&.key?('@id')
            errors << "#{filename}: transform produced incomplete entity/entry pair"
            next
          end

          @exporter.add_node(entity: r[:entity], entry: r[:entry], source: source)
          @search_indexer.add(r[:entity], r[:entry])

          source_graph << r[:entity]
          source_graph << r[:entry]
          added += 1
        end

        added
      end

      # Find input directory and its loadable YAML files for source
      #
      # Preference is eligibility-based, not existence-based: the first
      # candidate holding at least one eligible YAML file wins, so a
      # stale processed/ directory (empty or holding only _index.yaml)
      # no longer shadows curated YAML under sources/sanction-lists/.
      # When no candidate is eligible, the legacy existence-based chain
      # decides and the legacy (non-recursive, unfiltered) file set is
      # loaded, so failure and ingestion semantics for those
      # directories stay unchanged. Selection and loading derive from
      # one memoized resolution per directory (#resolve_yaml_files).
      # @param source [Symbol] source code
      # @return [Array(String, Array<String>), nil] directory and files
      def find_input_dir(source)
        explicit_input(source) || auto_input(source)
      end

      # Resolve the explicit --input-dir option, keeping the legacy
      # precedence: the per-source subdirectory wins whenever it
      # exists (a base holding per-source subdirectories must never be
      # loaded as one source), then the base directory with its legacy
      # file set. The subdirectory upgrades to the eligible set when
      # one is found, so nested per-source layouts load; an explicit
      # path that exists but holds nothing is still returned
      # (surfacing "No YAML files found") rather than silently falling
      # through to auto-detection, which would mask a mistyped path.
      # @param source [Symbol] source code
      # @return [Array(String, Array<String>), nil] directory and files
      def explicit_input(source)
        return nil unless options[:input_dir]

        sub = File.join(options[:input_dir], source.to_s)
        base = options[:input_dir]

        if Dir.exist?(sub)
          views = resolve_yaml_files(sub)
          files = views[:eligible].any? ? views[:chosen] : views[:legacy]
          return [sub, files]
        end
        return [base, resolve_yaml_files(base)[:legacy]] if Dir.exist?(base)

        nil
      end

      # Auto-detection: the first candidate holding eligible YAML, or
      # the legacy existence-based fallback. One memo per call keeps
      # every directory resolved at most once, so the eligibility
      # decision and the fallback's returned file list always come
      # from the same resolution of that directory.
      # @param source [Symbol] source code
      # @return [Array(String, Array<String>), nil] directory and files
      def auto_input(source)
        views_by_dir = Hash.new do |memo, dir|
          memo[dir] = resolve_yaml_files(dir)
        end

        candidate_input_dirs(source).each do |dir|
          views = views_by_dir[dir]
          return [dir, views[:chosen]] if views[:eligible].any?
        end

        dir = existing_input_dir(source)
        dir ? [dir, views_by_dir[dir][:legacy]] : nil
      end

      # Auto-detection candidates in legacy order — processed/, then
      # sources/sanction-lists/ (data-cn format), then raw/<latest
      # date>, each for the underscore and hyphen repo namings, then
      # the cache
      # @param source [Symbol] source code
      # @return [Array<String>] candidate directories
      def candidate_input_dirs(source)
        candidates = []

        if options[:sources_dir]
          %w[processed sources/sanction-lists].each do |subpath|
            data_repo_names(source).each do |repo|
              candidates << File.join(options[:sources_dir], repo, subpath)
            end
          end

          data_repo_names(source).each do |repo|
            raw_path = File.join(options[:sources_dir], repo, 'raw')
            candidates << find_latest_subdir(raw_path)
          end
        end

        candidates << find_latest_subdir(File.join(cache_dir, 'raw',
                                                   source.to_s))
        candidates.compact
      end

      # Underscore and hyphen data repository names for a source
      # (eu_vessels -> data-eu_vessels, data-eu-vessels)
      # @param source [Symbol] source code
      # @return [Array<String>] unique data-* directory names
      def data_repo_names(source)
        ["data-#{source}", "data-#{source.to_s.gsub('_', '-')}"].uniq
      end

      # Legacy existence-based directory chain (including the
      # historical early nil return for a raw/ directory without
      # dated subdirectories)
      # @param source [Symbol] source code
      # @return [String, nil] input directory path
      def existing_input_dir(source)
        if options[:sources_dir]
          %w[processed sources/sanction-lists].each do |subpath|
            data_repo_names(source).each do |repo|
              path = File.join(options[:sources_dir], repo, subpath)
              return path if Dir.exist?(path)
            end
          end

          data_repo_names(source).each do |repo|
            raw_path = File.join(options[:sources_dir], repo, 'raw')
            return find_latest_subdir(raw_path) if Dir.exist?(raw_path)
          end
        end

        cache_raw = File.join(cache_dir, 'raw', source.to_s)
        return find_latest_subdir(cache_raw) if Dir.exist?(cache_raw)

        nil
      end

      # Resolve a directory's YAML tiers once and derive the three
      # views discovery uses, so the eligibility decision and the
      # returned load list always come from the same resolution:
      # - :eligible — the selection predicate: regular files from the
      #   legacy tiers (entities/ subdirectory, flat files, one-level
      #   list directories — data-cn format), plus a recursive tier
      #   when those hold no regular direct YAML, reaching lists
      #   nested more than one level deep (data-jp). Only regular
      #   files count (a directory named like a YAML file must not
      #   make a candidate eligible), but eligibility is otherwise by
      #   name: malformed YAML stays eligible so source corruption
      #   surfaces through load errors and the health gates instead of
      #   silently falling through to another directory.
      # - :chosen — the load list for an eligibility winner: the
      #   unfiltered legacy set (layout anomalies like a directory
      #   named entity.yaml still surface as load errors exactly as
      #   before) plus the recursive regular files.
      # - :legacy — the loader's historical set (direct plus
      #   one-level tiers, unfiltered, never recursive) for existence
      #   fallbacks, keeping their semantics byte-identical.
      # @param dir [String, nil] directory to inspect
      # @return [Hash{Symbol=>Array<String>}] tier views
      def resolve_yaml_files(dir)
        empty = { eligible: [], chosen: [], legacy: [] }
        return empty if dir.nil? || !Dir.exist?(dir)

        direct = yaml_files_in(dir, 'entities') + yaml_files_in(dir)
        one_level = yaml_files_in(dir, '*')
        direct_regular = regular_files(direct)
        recursive = if direct_regular.empty?
                      regular_files(yaml_files_in(dir, '**'))
                    else
                      []
                    end
        legacy = (direct + one_level).uniq

        {
          eligible: (direct_regular + regular_files(one_level) +
                     recursive).uniq,
          chosen: (legacy + recursive).uniq,
          legacy: legacy
        }
      end

      # Eligible YAML files within a directory (see #resolve_yaml_files)
      # @param dir [String, nil] directory to inspect
      # @return [Array<String>] eligible YAML file paths
      def eligible_yaml_files(dir)
        resolve_yaml_files(dir)[:eligible]
      end

      # One glob tier of YAML entries, excluding metadata files
      # (basename starting with "_"). Patterns are globbed relative to
      # the directory (base:) so glob metacharacters in configured
      # paths are treated literally.
      # @param dir [String] directory to glob under
      # @param segments [Array<String>] intermediate path segments
      # @return [Array<String>] YAML entry paths
      def yaml_files_in(dir, *segments)
        patterns = %w[yaml yml].map do |ext|
          File.join(*segments, "*.#{ext}")
        end

        patterns.flat_map { |pattern| Dir.glob(pattern, base: dir) }
                .map { |relative| File.join(dir, relative) }
                .reject { |f| File.basename(f).start_with?('_') }
      end

      # Restrict paths to regular files (following symlinks)
      # @param paths [Array<String>] candidate paths
      # @return [Array<String>] regular file paths
      def regular_files(paths)
        paths.select { |f| File.file?(f) }
      end

      # Find latest subdirectory (by date)
      # @param base_dir [String] base directory
      # @return [String, nil] latest subdirectory
      def find_latest_subdir(base_dir)
        return nil unless Dir.exist?(base_dir)

        subdirs = Dir.children(base_dir).select do |child|
          path = File.join(base_dir, child)
          Dir.exist?(path) && child.match?(/^\d{4}-\d{2}-\d{2}$/)
        end.sort.reverse

        return nil if subdirs.empty?

        File.join(base_dir, subdirs.first)
      end

      # Find legal instruments directory
      # @return [String, nil] path to instruments directory
      def find_instruments_dir
        # Check sources_dir first
        sources_dir = options[:sources_dir]
        if sources_dir
          # Check for data-cn format: sources/legal-instruments/
          instruments_path = File.join(sources_dir, 'data-cn', 'sources', 'legal-instruments')
          return instruments_path if Dir.exist?(instruments_path)
        end

        # Check based on input_dir (sibling directory to legal-instruments)
        input_dir = options[:input_dir]
        if input_dir
          # input_dir might be .../sources/sanction-lists
          # so legal-instruments would be at .../sources/legal-instruments
          parent_dir = File.dirname(input_dir)
          instruments_path = File.join(parent_dir, 'legal-instruments')
          return instruments_path if Dir.exist?(instruments_path)
        end

        nil
      end

      # Find supporting data directory (document types, organizations)
      # @return [String, nil] path to supporting directory
      def find_supporting_dir
        # Check sources_dir first
        sources_dir = options[:sources_dir]
        if sources_dir
          # Check for data-cn format: sources/supporting/
          supporting_path = File.join(sources_dir, 'data-cn', 'sources', 'supporting')
          return supporting_path if Dir.exist?(supporting_path)
        end

        # Check based on input_dir (sibling directory to supporting)
        input_dir = options[:input_dir]
        if input_dir
          # input_dir might be .../sources/sanction-lists
          # so supporting would be at .../sources/supporting
          parent_dir = File.dirname(input_dir)
          supporting_path = File.join(parent_dir, 'supporting')
          return supporting_path if Dir.exist?(supporting_path)
        end

        nil
      end

      # Transform data using appropriate transformer
      # @param source [Symbol] source code
      # @param data [Hash] source data
      # @return [Hash] { entity: Hash, entry: Hash }
      def transform_data(source, data)
        require_relative '../transformers/registry'

        transformer = Ammitto::Transformers::Registry.get(source)
        return { entity: nil, entry: nil } unless transformer

        # Transform based on source
        case source
        when :uk
          transform_uk(transformer, data)
        when :eu
          transform_eu(transformer, data)
        when :un
          transform_un(transformer, data)
        when :us
          transform_us(transformer, data)
        when :wb
          transform_wb(transformer, data)
        when :au
          transform_au(transformer, data)
        when :ca
          transform_ca(transformer, data)
        when :ch
          transform_ch(transformer, data)
        when :cn
          transform_cn(transformer, data)
        when :ru
          transform_ru(transformer, data)
        when :nz
          transform_nz(transformer, data)
        when :tr
          transform_tr(transformer, data)
        when :eu_vessels
          transform_eu_vessels(transformer, data)
        when :jp
          transform_jp(transformer, data)
        when :un_vessels
          transform_un_vessels(transformer, data)
        else
          { entity: nil, entry: nil }
        end
      end

      # Transform UK data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_uk(transformer, data)
        require_relative '../sources/uk/designation'

        designation = Ammitto::Sources::Uk::Designation.from_yaml(data.to_yaml)
        result = transformer.transform(designation)

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Transform EU data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_eu(transformer, data)
        require_relative '../sources/eu/sanction_entity'

        # The fetch pipeline saves Eu::SanctionEntity YAML (one per record);
        # parsing with ProcessedEntity collapsed every EU id and dropped names
        entity = Ammitto::Sources::Eu::SanctionEntity.from_yaml(data.to_yaml)
        result = transformer.transform(entity)

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Transform UN data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_un(transformer, data)
        require_relative '../sources/un/individual'
        require_relative '../sources/un/entity'

        # Determine if individual or entity based on presence of person-specific fields
        # UN data uses snake_case in YAML (first_name, not firstName)
        is_individual = data.key?('gender') ||
                        data.key?('date_of_birth') ||
                        data.key?('place_of_birth') ||
                        data.key?('documents') ||
                        data.key?('nationalities') ||
                        data.key?('fourth_name')

        if is_individual
          source = Ammitto::Sources::Un::Individual.from_yaml(data.to_yaml)
          result = transformer.transform_individual(source)
        else
          source = Ammitto::Sources::Un::Entity.from_yaml(data.to_yaml)
          result = transformer.transform_entity(source)
        end

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Transform US data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_us(transformer, data)
        require_relative '../sources/us/sdn_entry'

        sdn_entry = Ammitto::Sources::Us::SdnEntry.from_yaml(data.to_yaml)
        result = transformer.transform(sdn_entry)

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Transform WB data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_wb(transformer, data)
        require_relative '../sources/wb/sanctioned_firm'

        firm = Ammitto::Sources::Wb::SanctionedFirm.from_yaml(data.to_yaml)
        result = transformer.transform(firm)

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Transform AU data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_au(transformer, data)
        require_relative '../sources/au/sanctions_list'

        # Detect record type: vessels carry imo_number, individuals carry
        # dates_of_birth; the rest are organizations
        source = if data.key?('imo_number')
                   Ammitto::Sources::Au::Vessel.from_yaml(data.to_yaml)
                 elsif data.key?('dates_of_birth')
                   Ammitto::Sources::Au::Individual.from_yaml(data.to_yaml)
                 else
                   Ammitto::Sources::Au::Organization.from_yaml(data.to_yaml)
                 end
        result = transformer.transform(source)

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Transform CA data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_ca(transformer, data)
        require_relative '../sources/ca/sanctions_list'

        # Use Record class - it handles both individuals and entities
        # The YAML has given_name, not first_name
        source = Ammitto::Sources::Ca::Record.from_yaml(data.to_yaml)
        result = transformer.transform(source)

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Transform CH data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_ch(transformer, data)
        require_relative '../sources/ch/sanctions_list'

        # The fetch pipeline saves bare Identity records
        # (SanctionsList#all_identities), not Target wrappers
        source = Ammitto::Sources::Ch::Identity.from_yaml(data.to_yaml)
        result = transformer.transform(source)

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Transform CN data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash, Array<Hash>] single result or array of results
      def transform_cn(transformer, data)
        # Check if this is the new data-cn YAML format
        if data.key?('announcement') && data.key?('sanction_details')
          transform_cn_announcement(transformer, data)
        elsif data.key?('announcement') && data.key?('measure_modifications')
          transform_cn_modification(transformer, data)
        else
          # The pre-#16 single-entity format is no longer supported; its
          # model (Cn::SanctionedEntity) was removed with cn/sanctions_list
          raise 'Unsupported CN source format (expected announcement-based YAML)'
        end
      end

      # Transform CN announcement (new YAML format)
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Array<Hash>] array of transformation results
      def transform_cn_announcement(transformer, data)
        require_relative '../sources/cn/announcement'

        announcement = Ammitto::Sources::Cn::Announcement.from_hash(data)
        result = transformer.transform_announcement(announcement)

        # Export SanctionGroup if present
        @exporter.add_group(result[:group], source: :cn) if result[:group]

        # Return array of entity/entry pairs
        result[:entities].zip(result[:entries]).map do |entity, entry|
          {
            entity: entity_to_hash(entity),
            entry: entry_to_hash(entry)
          }
        end
      end

      # Transform CN modification (new YAML format)
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash] modification data (no entities)
      def transform_cn_modification(transformer, data)
        require_relative '../sources/cn/measure_modification'

        modification = Ammitto::Sources::Cn::MeasureModification.from_hash(data)
        result = transformer.transform_modification(modification)

        # Return empty entity/entry - modifications are handled separately
        {
          entity: nil,
          entry: nil,
          modifications: result[:modifications]&.map do |m|
            m.to_hash
          rescue StandardError
            m
          end,
          announcement: result[:announcement]&.to_hash
        }
      end

      # Transform RU data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_ru(transformer, data)
        require_relative '../sources/ru/sanctions_list'

        source = Ammitto::Sources::Ru::SanctionedEntity.from_yaml(data.to_yaml)
        result = transformer.transform(source)

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Transform NZ data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_nz(transformer, data)
        require_relative '../sources/nz/sanctions_list'

        # Determine type
        source = case data['type']
                 when 'Individual'
                   Ammitto::Sources::Nz::Individual.from_yaml(data.to_yaml)
                 when 'Ship'
                   Ammitto::Sources::Nz::Ship.from_yaml(data.to_yaml)
                 else
                   Ammitto::Sources::Nz::Entity.from_yaml(data.to_yaml)
                 end
        result = transformer.transform(source)

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Transform TR data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_tr(transformer, data)
        require_relative '../sources/tr/sanctions_list'

        source = Ammitto::Sources::Tr::Entity.from_yaml(data.to_yaml)
        result = transformer.transform(source)

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Transform EU Vessels data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_eu_vessels(transformer, data)
        require_relative '../sources/eu_vessels/vessel'

        source = Ammitto::Sources::EuVessels::Vessel.from_yaml(data.to_yaml)
        result = transformer.transform(source)

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Transform JP data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_jp(transformer, data)
        require_relative '../sources/jp/entity'

        source = Ammitto::Sources::Jp::Entity.from_yaml(data.to_yaml)
        result = transformer.transform(source)

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Transform UN Vessels data
      # @param transformer [Object] transformer instance
      # @param data [Hash] source data
      # @return [Hash]
      def transform_un_vessels(transformer, data)
        require_relative '../sources/un_vessels/vessel'

        source = Ammitto::Sources::UnVessels::Vessel.from_yaml(data.to_yaml)
        result = transformer.transform(source)

        {
          entity: entity_to_hash(result[:entity]),
          entry: entry_to_hash(result[:entry])
        }
      end

      # Serializer producing the canonical camelCase JSON-LD shape
      # (@id/@type + context.jsonld terms). This is the single boundary
      # between harmonized models and every exported artifact — the exporters,
      # the search index, and the website all consume this vocabulary.
      # @return [Ammitto::Serialization::JsonLdSerializer]
      def json_ld_serializer
        @json_ld_serializer ||= Ammitto::Serialization::JsonLdSerializer.new
      end

      # Convert entity model to its canonical JSON-LD hash. Serialization
      # errors propagate to the per-file error collector — swallowing them
      # here would let the health gates count empty nodes as success.
      # @param entity [Object] entity model
      # @return [Hash, nil]
      def entity_to_hash(entity)
        return nil unless entity

        # Per-node @context is dropped; exporters add it at document level
        json_ld_serializer.serialize_entity(entity).except('@context')
      end

      # Convert entry model to its canonical JSON-LD hash (errors propagate)
      # @param entry [Object] entry model
      # @return [Hash, nil]
      def entry_to_hash(entry)
        return nil unless entry

        json_ld_serializer.serialize_entry(entry).except('@context')
      end

      # Get cache directory
      # @return [String]
      def cache_dir
        options[:cache_dir] || File.expand_path('~/.ammitto')
      end

      # Print summary of results
      # @param results [Array<Hash>] harmonize results
      # @return [void]
      def print_summary(results)
        success = results.count { |r| r[:status] == :success }
        failed = results.count { |r| r[:status] == :error }

        puts
        puts "Harmonize complete: #{success} succeeded, #{failed} failed"

        return unless failed.positive?

        puts 'Failed sources:'
        results.select { |r| r[:status] == :error }.each do |r|
          puts "  #{r[:code]}: #{r[:error]}"
        end
      end
    end
  end
end
