# frozen_string_literal: true

require 'fileutils'
require 'json'

module Ammitto
  # Pipeline orchestrates fetch → process → export workflow
  #
  # @example Basic usage
  #   pipeline = Ammitto::Pipeline.new(source: :eu)
  #   result = pipeline.run
  #
  class Pipeline
    # @return [Symbol] source code
    attr_reader :source

    # @return [String] cache directory
    attr_reader :cache_dir

    # @return [Boolean] verbose mode
    attr_reader :verbose

    # Initialize pipeline
    # @param source [Symbol] source code
    # @param cache_dir [String] cache directory
    # @param verbose [Boolean] verbose mode
    def initialize(source:, cache_dir: nil, verbose: false)
      @source = source.to_sym
      @cache_dir = cache_dir || File.expand_path('~/.ammitto')
      @verbose = verbose
    end

    # Run the pipeline
    # @return [Hash] pipeline result
    def run
      puts "[#{source}] Running pipeline..." if verbose

      # Ensure directories exist
      ensure_directories

      # Get extractor
      extractor = get_extractor
      unless extractor
        return {
          status: :error,
          error: "No extractor available for source: #{source}"
        }
      end

      # Fetch raw data
      raw_data = extractor.fetch
      puts "[#{source}] Fetched raw data" if verbose

      # Extract entities
      entities = extractor.extract_entities(raw_data)
      puts "[#{source}] Extracted #{entities.length} entities" if verbose

      # Extract entries
      entries = extractor.extract_entries(raw_data)
      puts "[#{source}] Extracted #{entries.length} entries" if verbose

      # Write output
      write_output(entities, entries)

      {
        status: :success,
        entities: entities.length,
        entries: entries.length
      }
    rescue StandardError => e
      puts "[#{source}] ERROR: #{e.message}" if verbose
      puts e.backtrace.first(5).join("\n") if verbose
      {
        status: :error,
        error: e.message
      }
    end

    private

    # Ensure all necessary directories exist
    # @return [void]
    def ensure_directories
      FileUtils.mkdir_p(File.join(cache_dir, 'raw', source.to_s))
      FileUtils.mkdir_p(File.join(cache_dir, 'processed', source.to_s))
      FileUtils.mkdir_p(File.join(cache_dir, 'cache', 'sources', source.to_s))
    end

    # Get extractor for source
    # @return [Object, nil] extractor instance
    def get_extractor
      require_relative 'extractors/registry'
      klass = Ammitto::Extractors::Registry.get(source)
      return nil unless klass

      klass.new
    end

    # Write output files
    # @param entities [Array<Hash>] entities
    # @param entries [Array<Hash>] entries
    # @return [void]
    def write_output(entities, entries)
      # Write JSON-LD output
      graph = []

      entities.each do |entity|
        graph << entity
      end

      entries.each do |entry|
        graph << entry
      end

      output = {
        '@context' => 'https://www.ammitto.org/ontology/context.jsonld',
        '@graph' => graph
      }

      output_path = File.join(cache_dir, 'cache', 'sources', source.to_s, "#{source}.jsonld")
      File.write(output_path, JSON.pretty_generate(output))
      puts "[#{source}] Wrote #{output_path}" if verbose

      # Write metadata
      metadata = {
        source: source.to_s,
        entities: entities.length,
        entries: entries.length,
        last_updated: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
      }

      metadata_path = File.join(cache_dir, 'cache', 'sources', source.to_s, 'metadata.json')
      File.write(metadata_path, JSON.pretty_generate(metadata))
    end
  end
end
