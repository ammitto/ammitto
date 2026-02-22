# frozen_string_literal: true

require 'json'

module Ammitto
  module Schema
    # Context provides the JSON-LD context for Ammitto data
    #
    # @example Getting the context
    #   Ammitto.schema.context_url
    #   # => "https://ammitto.org/schema/v1/context.jsonld"
    #
    #   Ammitto.schema.context
    #   # => { "@context" => { ... } }
    #
    class Context
      # JSON-LD context URL
      CONTEXT_URL = 'https://ammitto.org/schema/v1/context.jsonld'

      # Schema version
      VERSION = '1.0.0'

      class << self
        # @return [String] the context URL
        def context_url
          CONTEXT_URL
        end

        # @return [Hash] the full JSON-LD context
        def context
          @context ||= build_context
        end

        # @return [String] JSON representation of the context
        def to_json(*_args)
          JSON.pretty_generate(context)
        end

        private

        def build_context
          {
            '@context' => {
              '@vocab' => 'https://ammitto.org/schema/v1/',
              'xsd' => 'http://www.w3.org/2001/XMLSchema#',
              'schema' => 'https://schema.org/',
              'prov' => 'http://www.w3.org/ns/prov#',
              'owl' => 'http://www.w3.org/2002/07/owl#',
              'skos' => 'http://www.w3.org/2004/02/skos/core#',

              # Entity types
              'Entity' => { '@id' => 'Entity' },
              'PersonEntity' => { '@id' => 'PersonEntity' },
              'OrganizationEntity' => { '@id' => 'OrganizationEntity' },
              'VesselEntity' => { '@id' => 'VesselEntity' },
              'AircraftEntity' => { '@id' => 'AircraftEntity' },
              'SanctionEntry' => { '@id' => 'SanctionEntry' },
              'SanctionRegime' => { '@id' => 'SanctionRegime' },
              'SanctionEffect' => { '@id' => 'SanctionEffect' },
              'LegalInstrument' => { '@id' => 'LegalInstrument' },
              'OfficialAnnouncement' => { '@id' => 'OfficialAnnouncement' },

              # Entity attributes
              'names' => { '@id' => 'schema:name', '@container' => '@set' },
              'entityType' => { '@id' => 'entityType', '@type' => '@vocab' },
              'hasSanctionEntry' => {
                '@id' => 'hasSanctionEntry',
                '@type' => '@id',
                '@container' => '@set'
              },

              # Sanction attributes
              'authority' => { '@id' => 'authority', '@type' => '@id' },
              'regime' => { '@id' => 'regime' },
              'listType' => { '@id' => 'listType' },
              'legalBases' => { '@id' => 'legalBasis', '@container' => '@set' },
              'effects' => { '@id' => 'effect', '@container' => '@set' },
              'reasons' => { '@id' => 'reason', '@container' => '@set' },
              'period' => { '@id' => 'period' },
              'status' => { '@id' => 'status', '@type' => '@vocab' },
              'announcement' => { '@id' => 'announcement' },

              # Effect types
              'effectType' => { '@id' => 'effectType', '@type' => '@vocab' },
              'asset_freeze' => 'asset_freeze',
              'travel_ban' => 'travel_ban',
              'trade_restriction' => 'trade_restriction',
              'debarment' => 'debarment',
              'sectoral_sanction' => 'sectoral_sanction',

              # Reason categories
              'reasonCategory' => { '@id' => 'reasonCategory', '@type' => '@vocab' },
              'terrorism' => 'terrorism',
              'proliferation' => 'proliferation',
              'human_rights_violations' => 'human_rights_violations',
              'corruption' => 'corruption',
              'aggression' => 'aggression',

              # Raw source data
              'rawSourceData' => { '@id' => 'rawSourceData' },
              'sourceFile' => { '@id' => 'sourceFile' },
              'rawContent' => { '@id' => 'rawContent' },
              'sourceSpecificFields' => { '@id' => 'sourceSpecificFields' },

              # Vessel attributes
              'imoNumber' => { '@id' => 'imoNumber' },
              'mmsi' => { '@id' => 'mmsi' },
              'callSign' => { '@id' => 'callSign' },
              'flagState' => { '@id' => 'flagState' },
              'vesselType' => { '@id' => 'vesselType' },
              'owner' => { '@id' => 'owner', '@type' => '@id' },
              'operator' => { '@id' => 'operator', '@type' => '@id' },

              # Person attributes
              'birthInfo' => { '@id' => 'birthInfo', '@container' => '@set' },
              'nationalities' => { '@id' => 'nationality', '@container' => '@set' },
              'gender' => { '@id' => 'schema:gender' },
              'identifications' => {
                '@id' => 'identification',
                '@container' => '@set'
              },

              # Organization attributes
              'registrationNumber' => { '@id' => 'registrationNumber' },
              'incorporationDate' => {
                '@id' => 'incorporationDate',
                '@type' => 'xsd:date'
              },
              'legalForm' => { '@id' => 'legalForm' },
              'beneficialOwners' => {
                '@id' => 'beneficialOwner',
                '@type' => '@id',
                '@container' => '@set'
              },

              # Common attributes
              'title' => { '@id' => 'schema:title' },
              'url' => { '@id' => 'schema:url', '@type' => '@id' },
              'publishedDate' => {
                '@id' => 'schema:datePublished',
                '@type' => 'xsd:date'
              },
              'author' => { '@id' => 'schema:author' },

              # Linked data
              'sameAs' => {
                '@id' => 'owl:sameAs',
                '@type' => '@id',
                '@container' => '@set'
              },
              'seeAlso' => { '@id' => 'rdfs:seeAlso', '@type' => '@id' }
            }
          }
        end
      end
    end
  end
end
