# frozen_string_literal: true

# Ammitto Sanctions Ontology
#
# This module provides a fully harmonized, OOP, MECE ontology for
# representing sanctions data from multiple sources.
#
# Design Principles:
# - MECE: Each concept defined once, all concepts cover the domain
# - OOP: Proper class hierarchy with single responsibility
# - Open/Closed: Open for extension, closed for modification
#
# Class Hierarchy:
# - Types: Enumerations (EntityType, IDType, EffectType, etc.)
# - ValueObjects: Immutable data containers (NameVariant, Address, etc.)
# - Entities: Objects with identity (PersonEntity, OrganizationEntity, etc.)
# - Sanction: Sanction-specific classes (Authority, SanctionEntry, etc.)
# - SanctionsList: List definitions (Anti-Sanction List, SDN List, etc.)
#
# == Normalized Knowledge Graph Structure
#
# The knowledge graph follows a normalized structure:
#
# 1. ENTITIES are LIST-AGNOSTIC
#    - An entity (person/organization/vessel) exists independently
#    - Same entity can appear on multiple lists
#    - IRI: /entity/{source}/{local_id}
#
# 2. LISTS define sanctions regimes
#    - Each list has metadata (name, authority, legal basis)
#    - IRI: /list/{source}/{list_type}
#
# 3. ENTRIES link entities to lists
#    - Entry is the junction record (entity + list)
#    - Contains list-specific data (measures, dates, status)
#    - IRI: /entry/{source}/{list_type}/{local_id}
#
# 4. ANNOUNCEMENTS are LIST-AGNOSTIC
#    - An announcement can affect multiple lists
#    - IRI: /announcement/{source}/{local_id}
#
# 5. LEGAL INSTRUMENTS are LIST-AGNOSTIC
#    - A law/regulation can authorize multiple lists
#    - IRI: /legal_instrument/{source}/{local_id}
#

require_relative 'utils/presence'
require_relative 'ontology/types'
require_relative 'ontology/value_objects'
require_relative 'ontology/entities'
require_relative 'ontology/sanction'
require_relative 'ontology/sanctions_list'
require_relative 'ontology/neo4j_adapter'
require_relative 'ontology/schema'
require_relative 'ontology/document_type'
require_relative 'ontology/organization'
require_relative 'utils/iri_sanitizer'
require_relative 'utils/list_types_registry'

module Ammitto
  # Ontology module contains all harmonized data models
  module Ontology
    # Base URI for all ontology identifiers
    BASE_URI = 'https://www.ammitto.org'

    # Ontology version
    VERSION = '2.0.0'

    class << self
      # Generate an entity URI (LIST-AGNOSTIC).
      #
      # Entities can appear on multiple lists, so they don't include list_type.
      #
      # @param source [Symbol, String] source code (eu, un, us, etc.)
      # @param local_id [String] local entity identifier
      # @return [String]
      #
      # @example
      #   entity_uri("cn", "mitsubishi-heavy-industries")
      #   # => "https://www.ammitto.org/entity/cn/mitsubishi-heavy-industries"
      #
      def entity_uri(source, local_id)
        Utils::IriSanitizer.entity_iri(source, local_id)
      end

      # Generate an entry URI (LIST-SPECIFIC).
      #
      # Entries are junction records linking entities to specific lists.
      #
      # @param source [Symbol, String] source code (eu, un, us, etc.)
      # @param list_type [String] list type (e.g., "import-export-control-list")
      # @param local_id [String] local entry identifier
      # @return [String]
      #
      # @example Same entity, different lists
      #   entry_uri("cn", "import-export-control-list", "mitsubishi-heavy-industries")
      #   # => "https://www.ammitto.org/entry/cn/import-export-control-list/mitsubishi-heavy-industries"
      #
      #   entry_uri("cn", "unreliable-entity-list", "mitsubishi-heavy-industries")
      #   # => "https://www.ammitto.org/entry/cn/unreliable-entity-list/mitsubishi-heavy-industries"
      #
      def entry_uri(source, list_type, local_id)
        Utils::IriSanitizer.entry_iri(source, list_type, local_id)
      end

      # Generate a list URI.
      #
      # @param source [Symbol, String] source code
      # @param list_type [String] list type identifier
      # @return [String]
      #
      # @example
      #   list_uri("cn", "import-export-control-list")
      #   # => "https://www.ammitto.org/list/cn/import-export-control-list"
      #
      def list_uri(source, list_type)
        Utils::IriSanitizer.list_type_iri(source, list_type)
      end

      # Generate an announcement URI (LIST-AGNOSTIC).
      #
      # Announcements can affect multiple lists.
      #
      # @param source [Symbol, String] source code
      # @param local_id [String] local announcement identifier
      # @return [String]
      #
      # @example
      #   announcement_uri("cn", "mofcom-2026-11")
      #   # => "https://www.ammitto.org/announcement/cn/mofcom-2026-11"
      #
      def announcement_uri(source, local_id)
        Utils::IriSanitizer.announcement_iri(source, local_id)
      end

      # Generate a legal instrument URI (LIST-AGNOSTIC).
      #
      # Legal instruments can authorize multiple lists.
      #
      # @param source [Symbol, String] source code
      # @param local_id [String] local legal instrument identifier
      # @return [String]
      #
      # @example
      #   legal_instrument_uri("cn", "export-control-law")
      #   # => "https://www.ammitto.org/legal_instrument/cn/export-control-law"
      #
      def legal_instrument_uri(source, local_id)
        Utils::IriSanitizer.legal_instrument_iri(source, local_id)
      end

      # Generate an authority URI.
      # @param code [Symbol, String] authority code
      # @return [String]
      def authority_uri(code)
        Utils::IriSanitizer.authority_uri(code)
      end

      # Generate a source URI.
      # @param source [Symbol, String] source code
      # @return [String]
      def source_uri(source)
        Utils::IriSanitizer.source_uri(source)
      end

      # Get all known sanctions lists.
      # @return [Hash<String, SanctionsList>]
      def lists
        @lists ||= build_lists.freeze
      end

      # Get a specific list by source and list_type.
      # @param source [String] Source code
      # @param list_type [String] List type identifier
      # @return [SanctionsList, nil]
      def list(source, list_type)
        lists["#{source}/#{list_type}"]
      end

      # Get all lists for a source.
      # @param source [String] Source code
      # @return [Array<SanctionsList>]
      def lists_for_source(source)
        lists.values.select { |l| l.source == source }
      end

      # Get all known authorities
      # @return [Hash<String, Authority>]
      def authorities
        @authorities ||= {
          'eu' => Sanction::Authority.new(
            id: 'eu',
            name: 'European Union',
            country_code: 'EU',
            url: 'https://finance.ec.europa.eu/eu-and-world/sanctions-restrictive-measures_en'
          ),
          'un' => Sanction::Authority.new(
            id: 'un',
            name: 'United Nations',
            country_code: 'UN',
            url: 'https://www.un.org/securitycouncil/sanctions/information'
          ),
          'us' => Sanction::Authority.new(
            id: 'us',
            name: 'United States (OFAC)',
            country_code: 'US',
            url: 'https://ofac.treasury.gov/sanctions-programs-and-country-information'
          ),
          'uk' => Sanction::Authority.new(
            id: 'uk',
            name: 'United Kingdom',
            country_code: 'GB',
            url: 'https://www.gov.uk/government/publications/financial-sanctions-consolidated-list-of-targets'
          ),
          'au' => Sanction::Authority.new(
            id: 'au',
            name: 'Australia (DFAT)',
            country_code: 'AU',
            url: 'https://www.dfat.gov.au/international-relations/security/sanctions'
          ),
          'ca' => Sanction::Authority.new(
            id: 'ca',
            name: 'Canada',
            country_code: 'CA',
            url: 'https://www.international.gc.ca/world-monde/international_relations-relations_internationales/sanctions/index.aspx'
          ),
          'ch' => Sanction::Authority.new(
            id: 'ch',
            name: 'Switzerland (SECO)',
            country_code: 'CH',
            url: 'https://www.seco.admin.ch/en/searching-for-subjects-sanctions'
          ),
          'cn' => Sanction::Authority.new(
            id: 'cn',
            name: 'China (MOFCOM)',
            country_code: 'CN',
            url: 'https://english.mofcom.gov.cn/'
          ),
          'ru' => Sanction::Authority.new(
            id: 'ru',
            name: 'Russia (MID)',
            country_code: 'RU',
            url: 'https://mid.ru/'
          ),
          'nz' => Sanction::Authority.new(
            id: 'nz',
            name: 'New Zealand (MFAT)',
            country_code: 'NZ',
            url: 'https://www.mfat.govt.nz/en/peace-rights-and-security/sanctions/'
          ),
          'tr' => Sanction::Authority.new(
            id: 'tr',
            name: 'Turkey (HMB)',
            country_code: 'TR',
            url: 'https://en.hmb.gov.tr/fcib-sanctions'
          ),
          'jp' => Sanction::Authority.new(
            id: 'jp',
            name: 'Japan (METI)',
            country_code: 'JP',
            url: 'https://www.meti.go.jp/policy/anpo/english/law/doc/EndUserListE.html'
          ),
          'wb' => Sanction::Authority.new(
            id: 'wb',
            name: 'World Bank',
            country_code: 'INT',
            url: 'https://www.worldbank.org/en/projects-operations/procurement/debarred-firms'
          ),
          'eu_vessels' => Sanction::Authority.new(
            id: 'eu_vessels',
            name: 'EU (Denmark DMA)',
            country_code: 'EU',
            url: 'https://dma.dk/'
          ),
          'un_vessels' => Sanction::Authority.new(
            id: 'un_vessels',
            name: 'UN (1718 Committee)',
            country_code: 'UN',
            url: 'https://www.un.org/securitycouncil/sanctions/1718'
          )
        }.freeze
      end

      # Get authority by code
      # @param code [Symbol, String]
      # @return [Authority, nil]
      def authority(code)
        authorities[code.to_s]
      end

      private

      def build_lists
        lists = {}
        Utils::ListTypesRegistry::SOURCE_LIST_TYPES.each do |source, list_types|
          list_types.each do |list_type, info|
            key = "#{source}/#{list_type}"
            lists[key] = SanctionsList.new(
              source: source,
              list_type: list_type,
              name: info[:name] || info['name'],
              name_chinese: info[:name_chinese] || info['name_chinese'],
              name_russian: info[:name_russian] || info['name_russian'],
              authority: info[:authority] || info['authority'],
              description: info[:description] || info['description'],
              url: info[:url] || info['url'],
              established_date: info[:established_date] || info['established_date'],
              legal_instrument_ids: info[:legal_instrument_ids] || info['legal_instrument_ids'] || []
            )
          end
        end
        lists
      end
    end
  end
end
