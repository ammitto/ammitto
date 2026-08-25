# frozen_string_literal: true

module Ammitto
  module Config
    # Default configuration values for the Ammitto gem
    #
    # This module provides the baseline defaults that can be overridden
    # by programmatic configuration or environment variables.
    #
    # Priority: ENV > Programmatic API > Defaults
    module Defaults
      # Default cache directory
      CACHE_DIR = File.expand_path('~/.ammitto')

      # Default API base URL. The host here is a correctness constraint,
      # not a preference: ApiClient builds its Faraday connection with no
      # redirect middleware, so a 3xx is not `success?` and every fetch
      # raises. `https://ammitto.org/api/v1` answers 301 to the www host,
      # which made `Ammitto.search` fail on all fifteen sources with
      # "Failed to download <code> data". www.ammitto.org answers 200.
      #
      # This is separate from the context IRI, which the producer emits
      # WITHOUT www (Schema::Context::CONTEXT_URL). That one is an
      # identifier and is never fetched, so it stays as it is.
      API_BASE_URL = 'https://www.ammitto.org/api/v1'

      # Default cache TTL (1 hour in seconds)
      CACHE_TTL = 3600

      # Default connection timeout (10 seconds)
      CONNECTION_TIMEOUT = 10

      # Default read timeout (30 seconds)
      READ_TIMEOUT = 30

      # Default log level
      LOG_LEVEL = 'info'

      # Default sources to process
      DEFAULT_SOURCES = %i[eu un us wb].freeze

      # All available sources
      ALL_SOURCES = %i[eu un us wb uk au ca ch cn ru tr nz jp eu_vessels un_vessels].freeze

      # Sources with an automated fetch path IN THIS GEM. CN, RU and JP
      # are excluded so `fetch --all` does not fail on a source the gem
      # cannot fetch. An explicit `fetch cn` / `fetch ru` / `fetch jp`
      # still reports the missing fetch path rather than saving nothing
      # and calling it a success.
      #
      # The three are excluded for different reasons, worth keeping
      # straight:
      #
      # - cn has no automated source fetch, here or in data-cn, whose
      #   fetch.yml declares the implementation a TODO, prints "CN source
      #   not yet implemented" and suppresses the failure with `|| true`.
      # - jp IS automated — just not here. data-jp drives METI itself
      #   with scripts/download_foreign_user_list.rb (Mechanize against
      #   meti.go.jp) and scripts/convert_foreign_user_list_to_yaml.rb.
      #   The gap is where the automation lives, not whether it exists.
      # - ru has a source and cannot reach it: mid.ru serves an F5/TSPD
      #   JavaScript anti-bot challenge to non-browser clients, so
      #   Mechanize never sees the announcement links.
      #
      # Absence from this list says nothing about whether a source
      # PUBLISHES. cn and jp both publish, from YAML their own data repos
      # maintain. ru contributes nothing to the published graph — not
      # because data-ru is empty, but because nothing reaches it: the
      # deploy harmonizes ru with --allow-empty. `harmonize` runs over
      # ALL_SOURCES, not this list, so exclusion here withholds none of
      # them from the graph.
      FETCHABLE_SOURCES = (ALL_SOURCES - %i[cn ru jp]).freeze

      # Default output format
      DEFAULT_OUTPUT_FORMAT = 'jsonld'

      # Available output formats
      OUTPUT_FORMATS = %w[jsonld ttl nt rdfxml raw].freeze

      # Default raw data directory
      RAW_DATA_DIR = 'raw'

      # Default processed data directory
      PROCESSED_DATA_DIR = 'processed'

      # Default cache data directory
      CACHE_DATA_DIR = 'cache'

      # Default export format
      EXPORT_DIR = 'export'

      # Data repository directory (for harmonized JSON-LD output)
      # __FILE__ is lib/ammitto/config/defaults.rb
      # Go up 5 levels: config -> ammitto -> lib -> ammitto(gem) -> ammitto(project) -> data
      DATA_REPOSITORY = File.expand_path('../../../../data', __dir__)

      # Source data repositories parent directory
      # __FILE__ is lib/ammitto/config/defaults.rb
      # Go up 5 levels: config -> ammitto -> lib -> ammitto(gem) -> ammitto(project)
      SOURCES_DIR = File.expand_path('../../../..', __dir__)

      # Mapping of data-* directory names to source codes
      # Used for auto-detection and source-to-transformer mapping
      DATA_REPO_TO_SOURCE = {
        'data-eu' => :eu,
        'data-eu-vessels' => :eu_vessels,
        'data-un' => :un,
        'data-un-vessels' => :un_vessels,
        'data-us' => :us,
        'data-uk' => :uk,
        'data-au' => :au,
        'data-ca' => :ca,
        'data-ch' => :ch,
        'data-cn' => :cn,
        'data-ru' => :ru,
        'data-tr' => :tr,
        'data-nz' => :nz,
        'data-jp' => :jp,
        'data-wb' => :wb
      }.freeze

      # Auto-detect all data-* repositories in a directory
      # @param parent_dir [String] directory to scan (default: SOURCES_DIR)
      # @return [Array<Symbol>] detected source codes
      def self.detect_data_repositories(parent_dir = SOURCES_DIR)
        return [] unless Dir.exist?(parent_dir)

        Dir.glob(File.join(parent_dir, 'data-*'))
           .select { |d| Dir.exist?(d) }
           .map { |d| File.basename(d) }
           .filter_map { |name| DATA_REPO_TO_SOURCE[name] }
      end
    end
  end
end
