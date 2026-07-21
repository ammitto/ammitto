# frozen_string_literal: true

require 'mechanize'
require 'nokogiri'
require 'json'
require 'yaml'

module Ammitto
  module Data
    # China sanctions data handling
    #
    # This namespace provides fetchers, models, and transformers for
    # Chinese government sanctions data from multiple sources:
    #
    # - MOFCOM (Ministry of Commerce) - Unreliable Entity List, Export Control List
    # - MFA (Ministry of Foreign Affairs) - Anti-Sanctions List
    #
    # @example Fetch data from MOFCOM
    #   require 'ammitto/data/china'
    #
    #   extractor = Ammitto::Data::China::Mofcom::Extractor.new
    #   data = extractor.fetch
    #
    # @example Transform to harmonized format
    #   transformer = Ammitto::Data::China::Transformer.new
    #   result = transformer.transform(source_data)
    #
    module China
      # Base URI for Chinese government sources
      BASE_URIS = {
        mofcom: 'http://www.mofcom.gov.cn',
        mfa: 'http://www.mfa.gov.cn',
        npc: 'http://www.npc.gov.cn'
      }.freeze

      # List type codes used across the system
      LIST_TYPES = {
        anti_sanctions: 'anti-sanction-list',
        unreliable_entity: 'unreliable-entity-list',
        export_control: 'import-export-control-list'
      }.freeze

      # Regime codes for harmonized output
      REGIME_CODES = {
        anti_sanctions: 'CN_ANTI_SANCTIONS',
        unreliable_entity: 'CN_UNRELIABLE_ENTITY',
        export_control: 'CN_EXPORT_CONTROL'
      }.freeze

      class << self
        # Returns all available list types
        def list_types
          LIST_TYPES.keys
        end

        # Returns the URL slug for a list type
        # @param list_type [Symbol] the list type key
        # @return [String] the URL slug
        def list_slug(list_type)
          LIST_TYPES[list_type] || list_type.to_s.gsub('_', '-')
        end

        # Returns the regime code for a list type
        # @param list_type [Symbol] the list type key
        # @return [String] the regime code
        def regime_code(list_type)
          REGIME_CODES[list_type]
        end

        # Returns the source code
        def source_code
          :cn
        end
      end
    end
  end
end

# Load submodules
# Load utilities
require_relative 'china/schema_loader'
require_relative 'china/schema_resolver'
require_relative 'china/loader'

# Load core models
require_relative 'china/announcement'
require_relative 'china/entity'
require_relative 'china/list'
require_relative 'china/extractor'
require_relative 'china/validator'

# Load source-specific modules
require_relative 'china/mofcom/mofcom'
require_relative 'china/mfa/mfa'

# Load publishing format handlers
require_relative 'china/lists/anti_sanction_list'
require_relative 'china/lists/unreliable_entity_list'
require_relative 'china/lists/export_control_list'
