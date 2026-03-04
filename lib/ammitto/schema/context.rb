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
              'LocalizedString' => { '@id' => 'LocalizedString' },
              'LegalCitation' => { '@id' => 'LegalCitation' },
              'SanctionList' => { '@id' => 'SanctionList' },
              'SanctionGroup' => { '@id' => 'SanctionGroup' },
              'SanctionPeriodModification' => { '@id' => 'SanctionPeriodModification' },

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
              'seeAlso' => { '@id' => 'rdfs:seeAlso', '@type' => '@id' },

              # Provenance
              'sourceReferences' => {
                '@id' => 'prov:hadPrimarySource',
                '@container' => '@set'
              },
              'linkedEntities' => {
                '@id' => 'linkedEntity',
                '@container' => '@set'
              },
              'sourceCode' => { '@id' => 'sourceCode' },
              'referenceNumber' => { '@id' => 'referenceNumber' },
              'resolution' => { '@id' => 'resolution' },
              'fetchedAt' => { '@id' => 'fetchedAt', '@type' => 'xsd:dateTime' },

              # Entity Link
              'targetId' => { '@id' => 'targetId', '@type' => '@id' },
              'relationshipType' => { '@id' => 'relationshipType', '@type' => '@vocab' },
              'targetName' => { '@id' => 'targetName' },
              'targetType' => { '@id' => 'targetType' },

              # Tonnage
              'gt' => { '@id' => 'grossTonnage', '@type' => 'xsd:integer' },
              'dwt' => { '@id' => 'deadweightTonnage', '@type' => 'xsd:integer' },
              'nt' => { '@id' => 'netTonnage', '@type' => 'xsd:integer' },
              'grt' => { '@id' => 'grossRegisterTonnage', '@type' => 'xsd:integer' },
              'tonnage' => { '@id' => 'tonnage' },

              # BirthInfo full structure
              'birthDate' => { '@id' => 'schema:birthDate', '@type' => 'xsd:date' },
              'birthYear' => { '@id' => 'birthYear', '@type' => 'xsd:gYear' },
              'birthCity' => { '@id' => 'schema:birthPlace' },
              'birthCountry' => { '@id' => 'birthCountry' },

              # Address full structure
              'streetAddress' => { '@id' => 'schema:streetAddress' },
              'addressLocality' => { '@id' => 'schema:addressLocality' },
              'addressRegion' => { '@id' => 'schema:addressRegion' },
              'postalCode' => { '@id' => 'schema:postalCode' },
              'addressCountry' => { '@id' => 'schema:addressCountry' },

              # Identification full structure
              'idType' => { '@id' => 'idType', '@type' => '@vocab' },
              'idNumber' => { '@id' => 'idNumber' },
              'idCountry' => { '@id' => 'idCountry' },
              'issueDate' => { '@id' => 'issueDate', '@type' => 'xsd:date' },
              'expiryDate' => { '@id' => 'expiryDate', '@type' => 'xsd:date' },

              # Status History
              'fromStatus' => { '@id' => 'fromStatus', '@type' => '@vocab' },
              'toStatus' => { '@id' => 'toStatus', '@type' => '@vocab' },
              'statusHistory' => { '@id' => 'statusHistory', '@container' => '@set' },
              'suspensionEndDate' => { '@id' => 'suspensionEndDate', '@type' => 'xsd:date' },

              # Organization additional attributes
              'dissolutionDate' => { '@id' => 'dissolutionDate', '@type' => 'xsd:date' },
              'country' => { '@id' => 'country' },
              'countryIsoCode' => { '@id' => 'countryIsoCode' },
              'sector' => { '@id' => 'sector' },

              # LocalizedString properties
              'value' => { '@id' => 'value' },
              'lang' => { '@id' => 'lang' },
              'script' => { '@id' => 'script' },
              'isPrimary' => { '@id' => 'isPrimary', '@type' => 'xsd:boolean' },
              'isTransliteration' => { '@id' => 'isTransliteration', '@type' => 'xsd:boolean' },
              'transliterationSystem' => { '@id' => 'transliterationSystem' },

              # LegalCitation properties
              'legalInstrumentId' => { '@id' => 'legalInstrumentId', '@type' => '@id' },
              'articles' => { '@id' => 'articles', '@container' => '@set' },
              'sections' => { '@id' => 'sections', '@container' => '@set' },
              'paragraphs' => { '@id' => 'paragraphs', '@container' => '@set' },
              'citationType' => { '@id' => 'citationType' },
              'context' => { '@id' => 'context' },
              'quotedText' => { '@id' => 'quotedText', '@container' => '@set' },

              # SanctionList properties
              'source' => { '@id' => 'source' },
              'code' => { '@id' => 'code' },
              'description' => { '@id' => 'description' },
              'description_zh' => { '@id' => 'description_zh' },
              'description_en' => { '@id' => 'description_en' },
              'establishedDate' => { '@id' => 'establishedDate', '@type' => 'xsd:date' },
              'metadata' => { '@id' => 'metadata' },
              'legalCitations' => { '@id' => 'legalCitation', '@container' => '@set' },

              # SanctionGroup properties
              'announcementId' => { '@id' => 'announcementId', '@type' => '@id' },
              'listId' => { '@id' => 'listId', '@type' => '@id' },
              'entryIds' => { '@id' => 'entryId', '@type' => '@id', '@container' => '@set' },
              'sharedMeasures' => { '@id' => 'sharedMeasure', '@container' => '@set' },
              'sharedReasons' => { '@id' => 'sharedReason', '@container' => '@set' },
              'effectiveTime' => { '@id' => 'effectiveTime' },
              'entityCount' => { '@id' => 'entityCount', '@type' => 'xsd:integer' },
              'notes' => { '@id' => 'notes' },

              # SanctionPeriodModification properties
              'targetAnnouncementId' => { '@id' => 'targetAnnouncementId', '@type' => '@id' },
              'targetAnnouncementDate' => { '@id' => 'targetAnnouncementDate', '@type' => 'xsd:date' },
              'affectedEntityCount' => { '@id' => 'affectedEntityCount', '@type' => 'xsd:integer' },
              'affectedEntityNames' => { '@id' => 'affectedEntityName', '@container' => '@set' },
              'action' => { '@id' => 'action' },
              'untilDate' => { '@id' => 'untilDate', '@type' => 'xsd:date' },
              'untilTime' => { '@id' => 'untilTime' },
              'durationDays' => { '@id' => 'durationDays', '@type' => 'xsd:integer' },
              'durationDescription' => { '@id' => 'durationDescription' },
              'reason' => { '@id' => 'reason', '@container' => '@set' },

              # OfficialAnnouncement new properties
              'sanctionGroupIds' => { '@id' => 'sanctionGroupId', '@type' => '@id', '@container' => '@set' },
              'modifications' => { '@id' => 'modification', '@container' => '@set' },

              # SanctionEntry new properties
              'groupId' => { '@id' => 'groupId', '@type' => '@id' }
            }
          }
        end
      end
    end
  end
end
