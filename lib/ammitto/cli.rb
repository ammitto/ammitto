# frozen_string_literal: true

require 'thor'
require_relative 'config/defaults'
require_relative 'config/env_provider'
require_relative 'config/override_resolver'
require_relative 'options/registry'

module Ammitto
  # Ontology subcommand CLI
  class OntologyCLI < Thor
    desc 'fetch', 'Download ontology schemas'
    option :format, type: :string, default: 'jsonld', desc: 'Format (jsonld, ttl)'
    def fetch
      puts "Fetching ontology in #{options[:format]} format..."
      # TODO: Implement ontology fetch
    end

    desc 'validate FILE', 'Validate RDF file against ontology'
    def validate(file)
      puts "Validating #{file}..."
      # TODO: Implement validation
    end

    desc 'convert FILE', 'Convert between RDF formats'
    option :to, type: :string, required: true, desc: 'Target format'
    option :output, type: :string, desc: 'Output file'
    def convert(file)
      puts "Converting #{file} to #{options[:to]}..."
      # TODO: Implement conversion
    end

    desc 'query SPARQL', 'Execute SPARQL query'
    def query(sparql)
      puts "Executing query: #{sparql}"
      # TODO: Implement SPARQL query
    end

    desc 'stats', 'Show ontology statistics'
    def stats
      puts 'Ontology statistics:'
      puts '  Classes: 25'
      puts '  Properties: 80'
      puts '  Individuals: 8,551'
      # TODO: Calculate actual stats
    end
  end

  # Data subcommand CLI
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
    # Disable Thor's default handling of unknown options
    def self.exit_on_failure?
      false
    end

    # Map common mistakes to correct commands
    map %w[--version -v] => :version

    # Register common options for all commands
    Options::Registry.register_thor_options(self, %i[verbose log_level cache_dir])

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

      If no sources are specified with --all, fetches the specified sources only.

      Examples:
        ammitto fetch                           # Fetch first source
        ammitto fetch uk --format yaml          # Fetch UK data as YAML
        ammitto fetch uk --output-dir ./data    # Save to specific directory
        ammitto fetch --all                     # Fetch all sources
        ammitto fetch eu un --dry-run           # Show what would be fetched
    DESC
    option :dry_run, type: :boolean, default: false, desc: 'Show what would be done'
    option :force, type: :boolean, default: false, desc: 'Force re-download'
    option :all, type: :boolean, default: false, desc: 'Fetch all available sources'
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
    def process(*sources)
      require_relative 'cli/process_command'
      Cmd::ProcessCommand.new(options, sources).run
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

    # ---- Ontology Command ----

    desc 'ontology SUBCOMMAND', 'Ontology management commands'
    subcommand 'ontology', OntologyCLI

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
