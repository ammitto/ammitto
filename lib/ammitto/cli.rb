# frozen_string_literal: true

require 'thor'
require 'ammitto' # Ensure core library is loaded (sets up XML adapter, etc.)
require_relative 'config/defaults'
require_relative 'config/env_provider'
require_relative 'config/override_resolver'
require_relative 'options/registry'

module Ammitto
  # Namespace for command classes
  module Cmd
  end

  class DataCLI < Thor
    desc 'clone', 'Clone the data repository to local storage'
    option :force, type: :boolean, default: false, desc: 'Force re-clone'
    option :data_repository, type: :string, desc: 'Local path for repository'
    def clone
      require_relative 'cli/data_command'
      Cmd::DataCommand.new(options, 'clone').run
    end

    desc 'pull', 'Pull latest updates from remote'
    def pull
      require_relative 'cli/data_command'
      Cmd::DataCommand.new(options, 'pull').run
    end

    desc 'status', 'Show repository status'
    def status
      require_relative 'cli/data_command'
      Cmd::DataCommand.new(options, 'status').run
    end

    desc 'query', 'Query entities from the data'
    option :name, type: :string, desc: 'Name to search for'
    option :source, type: :string, desc: 'Source code to filter by'
    option :type, type: :string, desc: 'Entity type to filter by'
    option :country, type: :string, desc: 'Country to filter by'
    option :limit, type: :numeric, default: 20, desc: 'Maximum results'
    option :offset, type: :numeric, default: 0, desc: 'Offset for pagination'
    def query
      require_relative 'cli/data_command'
      Cmd::DataCommand.new(options, 'query').run
    end

    desc 'get ID', 'Get an entity by ID'
    def get(id)
      require_relative 'cli/data_command'
      Cmd::DataCommand.new(options, 'get', id).run
    end

    desc 'sources', 'List available sources'
    def sources
      require_relative 'cli/data_command'
      Cmd::DataCommand.new(options, 'sources').run
    end

    desc 'stats', 'Show data statistics'
    def stats
      require_relative 'cli/data_command'
      Cmd::DataCommand.new(options, 'stats').run
    end
  end

  # Namespace for command classes
  module Cmd
  end

  # Thor-based CLI for Ammitto
  #
  # Commands:
  #   ammitto version         - Show version
  #   ammitto sources         - List available sources
  #   ammitto status          - Show cache status
  #   ammitto fetch           - Download raw data from sources
  #   ammitto process         - Process raw data into harmonized models
  #   ammitto export          - Export to JSON-LD, Turtle, etc.
  #   ammitto search QUERY    - Search cached data
  #   ammitto data SUBCOMMAND - Data repository management
  #
  # @example Basic usage
  #   ammitto fetch eu un gb
  #   ammitto export jsonld --output-dir ./data
  #   ammitto search "Kim Jong" --sources un,eu
  #   ammitto data clone
  #   ammitto data query --name "Smith"
  #
  class CLI < Thor
    # Exit nonzero on command failure — required so CI/cron health gates can
    # detect failed runs instead of treating them as success
    def self.exit_on_failure?
      true
    end

    # Map common mistakes to correct commands
    map %w[--version -v] => :version

    # Register common options for all commands (--log-level was removed:
    # it was declared but never honored anywhere)
    Options::Registry.register_thor_options(self, %i[verbose cache_dir])

    # ---- Version Command ----

    desc 'version', 'Show Ammitto version'
    def version
      puts "ammitto #{Ammitto::VERSION}"
    end

    # ---- Sources Command ----

    desc 'sources', 'List available sanction sources'
    option :format, type: :string, default: 'table', desc: 'Output format (table, json)'
    def sources
      require_relative 'cli/sources_command'
      Cmd::SourcesCommand.new(options).run
    end

    # ---- Status Command ----

    desc 'status', 'Show cache and data status'
    option :format, type: :string, default: 'table', desc: 'Output format (table, json)'
    def status
      require_relative 'cli/status_command'
      Cmd::StatusCommand.new(options).run
    end

    # ---- Fetch Command ----

    desc 'fetch [SOURCES]', 'Download raw data from sources'
    long_desc <<~DESC
      Download raw sanction data from specified sources and save as YAML.

      Pass source codes to fetch specific sources, or use --all to fetch
      every source this command can reach. cn, ru and jp are skipped: it
      has no working path to any of them, and each still publishes from
      its own data repository.

      Examples:
        ammitto fetch uk --format yaml          # Fetch UK data as YAML
        ammitto fetch uk --output-dir ./data    # Save to specific directory
        ammitto fetch --all                     # Every reachable source
        ammitto fetch eu un --dry-run           # Show what would be fetched
    DESC
    option :dry_run, type: :boolean, default: false, desc: 'Show what would be done'
    option :all, type: :boolean, default: false,
                 desc: 'Fetch every source with a working fetch path (skips cn, ru, jp)'
    option :format, type: :string, default: 'yaml', desc: 'Output format (yaml, jsonld)'
    option :output_dir, type: :string, desc: 'Output directory for YAML files'
    def fetch(*sources)
      require_relative 'cli/fetch_command'
      Cmd::FetchCommand.new(options, sources).run
    end

    # ---- Harmonize Command ----

    desc 'harmonize [SOURCES]', 'Transform YAML source data to JSON-LD'
    long_desc <<~DESC
      Transform YAML source data to harmonized JSON-LD format.

      Reads YAML files from source data directories, transforms them using
      transformers, and exports as JSON-LD.

      Examples:
        ammitto harmonize                           # Harmonize default source
        ammitto harmonize uk --input-dir ./data    # From specific directory
        ammitto harmonize --all --sources-dir ../  # Harmonize all sources
        ammitto harmonize --all --combine          # Create combined output
    DESC
    option :input_dir, type: :string, desc: 'Input directory containing YAML files'
    option :sources_dir, type: :string, desc: 'Parent directory containing data-* repos'
    option :output_dir, type: :string, default: './api/v1', desc: 'Output directory for JSON-LD'
    option :all, type: :boolean, default: false, desc: 'Harmonize all sources'
    option :scan, type: :boolean, default: false, desc: 'Auto-detect data-* repositories'
    option :combine, type: :boolean, default: false, desc: 'Create combined all.jsonld'
    option :allow_empty, type: :string,
                         desc: 'Sources exempt from the health gates: zero entities, source errors, ' \
                               'missing aggregates, and the quality floors will not fail the run ' \
                               '(comma-separated). Per-file transform errors always fail.'
    option :report, type: :string,
                    desc: 'Write the run outcome as JSON to PATH, including per-source gate ' \
                          'failures. Written even when the gates fail, so CI can report what ' \
                          'broke without parsing this command output.'
    def harmonize(*sources)
      require_relative 'cli/harmonize_command'
      Cmd::HarmonizeCommand.new(options, sources).run
    end

    # ---- Process Command ----

    desc 'process [SOURCES]', 'Process raw data into harmonized models'
    long_desc <<~DESC
      Process downloaded raw data into harmonized Ammitto models.
      Converts source-specific formats to the unified ontology.

      Examples:
        ammitto process                # Process all fetched sources
        ammitto process eu gb          # Process specific sources
        ammitto process --force        # Force reprocessing
    DESC
    option :force, type: :boolean, default: false, desc: 'Force reprocessing'
    def process(*_sources)
      # The process pipeline implementation was removed in a5124d3; its role
      # is covered by `harmonize`. Deprecated: command removal planned for 2.0.
      raise Thor::Error,
            'The `process` command is no longer supported. ' \
            'Use `ammitto harmonize` to transform fetched YAML into JSON-LD.'
    end

    # ---- Export Command ----

    desc 'export [FORMAT]', 'Export data to specified format'
    long_desc <<~DESC
      Export processed data to various formats.

      Available formats:
        jsonld  - JSON-LD (primary format)
        ttl     - Turtle (RDF)
        nt      - N-Triples (RDF)
        rdfxml  - RDF/XML
        raw     - Source-specific YAML/JSON

      Examples:
        ammitto export jsonld                    # Export as JSON-LD
        ammitto export ttl --output-dir ./data   # Export Turtle to directory
        ammitto export all                       # Export all formats
    DESC
    option :output_dir, type: :string, default: './data', desc: 'Output directory'
    option :sources, type: :string, desc: 'Comma-separated sources to export'
    def export(format = 'jsonld')
      require_relative 'cli/export_command'
      Cmd::ExportCommand.new(options, format).run
    end

    # ---- Search Command ----

    desc 'search QUERY', 'Search entities by name'
    long_desc <<~DESC
      Search sanctioned entities by name or identifier.

      Entity types: person, organization, vessel, aircraft

      Examples:
        ammitto search "Kim Jong"                    # Search all sources
        ammitto search "Putin" --type person         # Filter by type
        ammitto search "123 AVIATION" --source eu    # Filter by source
        ammitto search "ship" --type vessel          # Search vessels
        ammitto search "IMO 12345" --format json     # Output as JSON
    DESC
    option :type, type: :string, desc: 'Entity type (person, organization, vessel, aircraft)'
    option :source, type: :string, desc: 'Source code to filter by'
    option :limit, type: :numeric, default: 50, desc: 'Maximum results'
    option :format, type: :string, default: 'text', desc: 'Output format (text, json)'
    option :data_repository, type: :string, desc: 'Path to data repository'
    def search(query)
      require_relative 'cli/search_command'
      Cmd::SearchCommand.new(options, query).run
    end

    # ---- Get Command ----

    desc 'get ID', 'Get an entity by ID'
    long_desc <<~DESC
      Fetch a specific entity by its identifier.

      ID formats supported:
        - Full URI: "https://www.ammitto.org/entity/un/KPi.066"
        - Short path: "un/KPi.066" or "entity/un/KPi.066"
        - Reference number: "KPi.066" (source-specific)

      Examples:
        ammitto get un/KPi.066              # Get by short path
        ammitto get eu/EU.10982.59          # Get EU entity
        ammitto get KPi.066 --format json   # Get by reference number
    DESC
    option :format, type: :string, default: 'text', desc: 'Output format (text, json)'
    option :data_repository, type: :string, desc: 'Path to data repository'
    def get(id)
      require_relative 'cli/get_command'
      Cmd::GetCommand.new(options, id).run
    end

    # ---- Data Command ----

    desc 'data SUBCOMMAND', 'Data repository management commands'
    long_desc <<~DESC
      Manage the local data repository containing harmonized entity data.

      Subcommands:
        clone   - Clone the data repository to local storage
        pull    - Pull latest updates from remote
        status  - Show repository status
        query   - Query entities from the data
        get     - Get an entity by ID
        sources - List available sources
        stats   - Show data statistics

      Examples:
        ammitto data clone                    # Clone the data repository
        ammitto data pull                     # Pull latest updates
        ammitto data query --name "Smith"     # Query by name
        ammitto data get eu-12345             # Get entity by ID
        ammitto data sources                  # List sources
    DESC
    subcommand 'data', DataCLI

    # ---- Source Command ----

    desc 'source COUNTRY SUBCOMMAND', 'Fetch data from country-specific sources'
    # wrap: false because Thor reflows a long_desc into one paragraph
    # otherwise, and this one is a list and a set of example command
    # lines. Without it `ammitto help source` renders the countries as
    # "china - MOFCOM and MFA lists japan - METI Foreign User List".
    long_desc <<~DESC, wrap: false
      Fetch sanction data from specific country authorities.

      Countries:
        china - MOFCOM and MFA lists
        japan - METI Foreign User List

      MOFA and MOF publish Japanese sanctions too; neither has a fetch
      path here, so neither is listed.

      Examples:
        ammitto source japan fetch meti              # Fetch METI Foreign User List
        ammitto source japan fetch meti --verbose    # Fetch with verbose output
        ammitto source japan fetch meti --output-dir ./data  # Save to custom directory
    DESC
    # Thor dispatches on the FIRST element of the argv it is handed, so the
    # subcommand has to lead. This passed `[country] + args`, which made
    # every documented invocation — `ammitto source japan fetch meti` —
    # look for a command named `japan`, print `Could not find command
    # "japan"` and, because SourceCommand defined no `exit_on_failure?`,
    # exit 0 having done nothing.
    #
    # @param country [String] country name, e.g. `japan`
    # @param subcommand [String] SourceCommand command, e.g. `fetch`
    # @param args [Array<String>] remaining arguments, e.g. the source code
    def source(country, subcommand, *args)
      require_relative 'cli/source_command'
      Cmd::SourceCommand.start([subcommand, country] + args)
    end

    # ---- Validate Command ----

    desc 'validate SUBCOMMAND', 'Validate data files against schemas'
    long_desc <<~DESC
      Validate source data files against JSON schemas.

      Subcommands:
        china  - Validate China sanctions data
        list   - List files and detected schema types
        schema - Show schema information

      Examples:
        ammitto validate china                          # Validate all China files
        ammitto validate china sources/ --verbose       # With detailed output
        ammitto validate list                           # List files and schemas
    DESC
    def validate(*args)
      require_relative 'cli/validate_command'
      Cmd::ValidateCommand.start(args)
    end

    # ---- Helper Methods ----

    private

    # Get resolved configuration
    # @return [Hash]
    def resolved_config
      @resolved_config ||= begin
        resolver = Config::OverrideResolver.new(
          verbose: options[:verbose],
          log_level: options[:log_level],
          cache_dir: options[:cache_dir]
        )
        resolver.resolve_all
      end
    end

    # Print error message
    # @param message [String] error message
    def error(message)
      warn "ERROR: #{message}"
      exit 1
    end

    # Print info message (respects verbose flag)
    # @param message [String] info message
    def info(message)
      puts message if options[:verbose]
    end
  end
end
