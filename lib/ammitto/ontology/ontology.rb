# frozen_string_literal: true

# Ammitto Harmonized Sanctions Ontology
#
# This module provides a unified data model for sanctions data from
# 15 international sources. It is designed to be:
# - OOP: Uses inheritance, encapsulation, and polymorphism via Lutaml::Model
# - MECE: Entity types are mutually exclusive and collectively exhaustive
# - Normalized: Uses ISO standard codes (ISO 3166-1, ISO 15924, ISO 639-1)
#
# @example Using the ontology
#   require 'ammitto/ontology'
#
#   # Create a person entity
#   person = Ammitto::Ontology::Entities::PersonEntity.new(
#     id: "https://www.ammitto.org/entity/eu/EU.123.45",
#     names: [Ammitto::Ontology::ValueObjects::NameVariant.new(
#       full_name: "Ivan Ivanov",
#       is_primary: true
#     )]
#   )
#
#   # Get authority from registry
#   eu = Ammitto::Ontology.authority("eu")
#

require_relative 'types'
require_relative 'value_objects'
require_relative 'entities'
require_relative 'sanction'

module Ammitto
  module Ontology
    # Registry of known sanctions authorities
    #
    # Provides quick access to authority objects by code.
    # Authorities are governmental or intergovernmental bodies that
    # impose sanctions (EU, UN, US OFAC, etc.)
    #
    # @example Getting an authority
    #   eu = Ammitto::Ontology.authority("eu")
    #   un = Ammitto::Ontology.authority("un")
    #
    class AuthorityRegistry
      # Known authorities with their metadata
      AUTHORITIES = {
        'au' => {
          name: 'Australia DFAT',
          country_code: 'AU',
          url: 'https://www.dfat.gov.au/international-relations/security/sanctions'
        },
        'ca' => {
          name: 'Canada Global Affairs',
          country_code: 'CA',
          url: 'https://www.international.gc.ca/world-monde/international_relations-relations_internationales/sanctions/index.aspx'
        },
        'ch' => {
          name: 'Switzerland SECO',
          country_code: 'CH',
          url: 'https://www.seco.admin.ch/seco/en/home/Aussenwirtschaftspolitik_Wirtschaftliche_Zusammenarbeit/Wirtschaftsbeziehungen/exportkontrollen-und-sanktionen/sanktionen-embargos.html'
        },
        'cn' => {
          name: 'China MOFCOM',
          country_code: 'CN',
          url: 'http://www.mofcom.gov.cn/'
        },
        'eu' => {
          name: 'European Union',
          country_code: 'EU',
          url: 'https://finance.ec.europa.eu/sanctions-dossier_en'
        },
        'eu_vessels' => {
          name: 'EU/Denmark DMA',
          country_code: 'EU',
          url: 'https://dma.dk/'
        },
        'jp' => {
          name: 'Japan METI',
          country_code: 'JP',
          url: 'https://www.meti.go.jp/'
        },
        'nz' => {
          name: 'New Zealand MFAT',
          country_code: 'NZ',
          url: 'https://www.mfat.govt.nz/en/peace-rights-and-security/sanctions/'
        },
        'ru' => {
          name: 'Russia MID',
          country_code: 'RU',
          url: 'https://www.mid.ru/'
        },
        'tr' => {
          name: 'Turkey HMB',
          country_code: 'TR',
          url: 'https://www.hmb.gov.tr/'
        },
        'uk' => {
          name: 'UK OFSI',
          country_code: 'GB',
          url: 'https://www.gov.uk/government/collections/financial-sanctions-regime-specific-consolidated-lists-and-releases'
        },
        'un' => {
          name: 'United Nations',
          country_code: 'UN',
          url: 'https://www.un.org/securitycouncil/sanctions/information'
        },
        'un_vessels' => {
          name: 'UN 1718 Committee',
          country_code: 'UN',
          url: 'https://www.un.org/securitycouncil/sanctions/1718'
        },
        'us' => {
          name: 'US OFAC',
          country_code: 'US',
          url: 'https://ofac.treasury.gov/'
        },
        'wb' => {
          name: 'World Bank',
          country_code: 'WB',
          url: 'https://www.worldbank.org/en/projects-operations/procurement/debarment-firms'
        }
      }.freeze

      # Get authority by code
      # @param code [String] the authority code (e.g., "eu", "un", "us")
      # @return [Sanction::Authority, nil] the authority or nil if not found
      def self.get(code)
        return nil unless AUTHORITIES.key?(code)

        info = AUTHORITIES[code]
        Sanction::Authority.new(
          id: code,
          name: info[:name],
          country_code: info[:country_code],
          url: info[:url]
        )
      end

      # Get all known authority codes
      # @return [Array<String>] list of authority codes
      def self.codes
        AUTHORITIES.keys
      end

      # Get all authorities
      # @return [Array<Sanction::Authority>] list of all authorities
      def self.all
        AUTHORITIES.keys.map { |code| get(code) }
      end

      # Check if authority code is known
      # @param code [String] the authority code
      # @return [Boolean] true if known
      def self.known?(code)
        AUTHORITIES.key?(code)
      end
    end

    class << self
      # Get authority by code
      # @param code [String] the authority code
      # @return [Sanction::Authority, nil] the authority or nil
      def authority(code)
        AuthorityRegistry.get(code)
      end

      # Get all known authority codes
      # @return [Array<String>] list of authority codes
      def authority_codes
        AuthorityRegistry.codes
      end

      # Create an entity of the appropriate type
      # @param entity_type [Symbol, String] type of entity
      # @param args [Hash] arguments for entity constructor
      # @return [Entities::Entity] appropriate entity subclass
      def create_entity(entity_type, **args)
        Entities.create(entity_type, **args)
      end
    end
  end
end
