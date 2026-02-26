# frozen_string_literal: true

# Core dependencies
require 'lutaml/model'

# Configure Lutaml::Model to use Nokogiri for XML parsing
Lutaml::Model::Config.configure do |config|
  config.xml_adapter_type = :nokogiri
end

# require "moxml"  # Not needed for export, available when needed
require 'faraday'
require 'multi_json'
require 'yaml'
require 'forwardable'

# Version
require_relative 'ammitto/version'

# Foundation
require_relative 'ammitto/configuration'
require_relative 'ammitto/logger'
require_relative 'ammitto/errors/base_error'

# Base models (must be loaded before entity types)
require_relative 'ammitto/models/name_variant'
require_relative 'ammitto/models/birth_info'
require_relative 'ammitto/models/address'
require_relative 'ammitto/models/identification'
require_relative 'ammitto/models/entity_link'
require_relative 'ammitto/models/contact_info'
require_relative 'ammitto/models/source_reference'
require_relative 'ammitto/models/tonnage'

# Entity models (depend on base models)
require_relative 'ammitto/models/entity'
require_relative 'ammitto/models/person_entity'
require_relative 'ammitto/models/organization_entity'
require_relative 'ammitto/models/vessel_entity'
require_relative 'ammitto/models/aircraft_entity'

# Sanction base models (must be loaded before sanction_entry)
require_relative 'ammitto/sanction/authority'
require_relative 'ammitto/sanction/sanction_regime'
require_relative 'ammitto/sanction/sanction_effect'
require_relative 'ammitto/sanction/sanction_reason'
require_relative 'ammitto/sanction/legal_instrument'
require_relative 'ammitto/sanction/list_type'
require_relative 'ammitto/sanction/temporal_period'
require_relative 'ammitto/sanction/status_change'
require_relative 'ammitto/sanction/official_announcement'
require_relative 'ammitto/sanction/raw_source_data'

# Sanction entry (depends on above)
require_relative 'ammitto/sanction/sanction_entry'

# Sources
require_relative 'ammitto/sources/registry'
require_relative 'ammitto/sources/base_source'
require_relative 'ammitto/sources/eu_source'
require_relative 'ammitto/sources/un_source'
require_relative 'ammitto/sources/us_source'
require_relative 'ammitto/sources/wb_source'
require_relative 'ammitto/sources/uk_source'
require_relative 'ammitto/sources/au_source'
require_relative 'ammitto/sources/ca_source'
require_relative 'ammitto/sources/ch_source'
require_relative 'ammitto/sources/cn_source'
require_relative 'ammitto/sources/ru_source'

# Client
require_relative 'ammitto/client/api_client'
require_relative 'ammitto/client/cache'
require_relative 'ammitto/client/cache_manager'

# Data repository
require_relative 'ammitto/data/repository'

# Search
require_relative 'ammitto/search/query_builder'
require_relative 'ammitto/search/result_set'

# Serialization
require_relative 'ammitto/serialization/json_ld_serializer'

# Schema
require_relative 'ammitto/schema/context'
require_relative 'ammitto/schema/validator'

# Transformers
require_relative 'ammitto/transformers/registry'

# Exporter
require_relative 'ammitto/exporter/simple_exporter'
require_relative 'ammitto/exporter/json_ld_export'

# Configure Moxml to use Nokogiri adapter (when needed)
# Moxml::Configuration.adapter = :nokogiri

module Ammitto
  class << self
    # Get the gem installation directory
    #
    # @return [String] the path to the gem installation directory
    def gem_dir
      @gem_dir ||= File.expand_path('..', __dir__)
    end

    # Search for sanctioned entities
    #
    # @param term [String] the search term
    # @param options [Hash] search options
    # @option options [Array<Symbol>] :sources list of source codes to search
    # @option options [Integer] :limit maximum number of results
    # @option options [Integer] :offset offset for pagination
    # @return [ResultSet] the search results
    def search(term, options = {})
      query = QueryBuilder.new(term, options).build
      ResultSet.new(query.execute)
    end

    # Refresh the local cache
    #
    # @param options [Hash] refresh options
    # @option options [Array<Symbol>] :sources list of source codes to refresh
    # @option options [Boolean] :all refresh all sources
    # @option options [Boolean] :force force refresh even if cache is fresh
    # @return [Hash] status of each source refresh
    def refresh_cache(options = {})
      CacheManager.refresh(options)
    end

    # Get cache status
    #
    # @return [Hash] status of cached sources
    def cache_status
      CacheManager.status
    end

    # Get list of available source codes
    #
    # @return [Array<Symbol>] list of source codes
    def sources
      Registry.codes
    end

    # Get the schema context
    #
    # @return [Schema::Context] the schema context
    def schema
      Schema::Context
    end

    # Get the data repository
    #
    # @param options [Hash] repository options
    # @option options [String] :local_path Local path for the repository
    # @option options [String] :remote_url Remote URL for the repository
    # @option options [Boolean] :verbose Enable verbose output
    # @return [Ammitto::Data::Repository] the repository instance
    def data_repository(options = {})
      @data_repository ||= {}
      key = options.hash
      @data_repository[key] ||= Data::Repository.new(
        local_path: options[:local_path] || configuration.data_repository,
        remote_url: options[:remote_url],
        verbose: options[:verbose] || configuration.verbose
      )
    end
  end
end
