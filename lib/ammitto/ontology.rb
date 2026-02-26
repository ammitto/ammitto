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
#

require_relative 'ontology/types'
require_relative 'ontology/value_objects'
require_relative 'ontology/entities'
require_relative 'ontology/sanction'

module Ammitto
  # Ontology module contains all harmonized data models
  module Ontology
    # Base URI for all ontology identifiers
    BASE_URI = 'https://www.ammitto.org'

    # Ontology version
    VERSION = '1.0.0'

    class << self
      # Generate an entity URI
      # @param source [Symbol, String] source code (eu, un, us, etc.)
      # @param reference [String] reference number from source
      # @return [String]
      def entity_uri(source, reference)
        "#{BASE_URI}/entity/#{source}/#{reference}"
      end

      # Generate an entry URI
      # @param source [Symbol, String] source code (eu, un, us, etc.)
      # @param reference [String] reference number from source
      # @return [String]
      def entry_uri(source, reference)
        "#{BASE_URI}/entry/#{source}/#{reference}"
      end

      # Generate an authority URI
      # @param code [Symbol, String] authority code
      # @return [String]
      def authority_uri(code)
        "#{BASE_URI}/authority/#{code}"
      end

      # Get all known authorities
      # @return [Hash<String, Authority>]
      def authorities
        @authorities ||= {
          'eu' => Sanction::Authority.new(
            id: 'eu',
            name: 'European Union',
            country_code: 'EU',
            url: 'https://finance.ec.europa.eu/sanctions-dossier_en'
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
            url: 'https://www.seco.admin.ch/seco/en/home/Aussenwirtschaft_Wirtschaftliche_Zusammenarbeit/Wirtschaftsbeziehungen/exportkontrollen-und-sanktionen/sanktionen-embargos.html'
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
    end
  end
end
