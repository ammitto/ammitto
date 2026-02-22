# frozen_string_literal: true

require_relative 'base_extractor'
require_relative 'registry'

module Ammitto
  module Extractors
    # WbExtractor extracts sanctions data from the World Bank (Debarment List)
    #
    # Source: https://apigwext.worldbank.org/dvns/v1/ols/SanctionedFirms
    #
    # World Bank data structure (JSON):
    # - Array of sanctioned firm objects
    #   - SUPP_ID, SUPP_NAME, SUPP_TYPE_CODE
    #   - DEBAR_FROM_DATE, DEBAR_TO_DATE
    #   - DEBAR_REASON, SUPP_ELIG_STAT
    #
    class WbExtractor < BaseExtractor
      # @return [Symbol] the source code
      def code
        :wb
      end

      # @return [String] authority name
      def authority_name
        'World Bank'
      end

      # @return [String] API endpoint
      def api_endpoint
        'https://apigwext.worldbank.org/dvns/v1/ols/SanctionedFirms'
      end

      # Fetch raw data from World Bank
      # @return [Array<Hash>]
      def fetch
        download_json(api_endpoint)
      end

      # Extract entities from World Bank JSON
      # @param data [Array<Hash>]
      # @return [Array<Hash>]
      def extract_entities(data)
        entities = []

        data.each do |firm|
          entity = extract_entity(firm)
          entities << entity if entity
        end

        entities
      end

      # Extract sanction entries from World Bank JSON
      # @param data [Array<Hash>]
      # @return [Array<Hash>]
      def extract_entries(data)
        entries = []

        data.each do |firm|
          entry = extract_entry(firm)
          entries << entry if entry
        end

        entries
      end

      private

      # Extract an entity
      # @param firm [Hash]
      # @return [Hash, nil]
      def extract_entity(firm)
        supp_id = firm['SUPP_ID']
        return nil unless supp_id

        entity_type = firm['SUPP_TYPE_CODE'] == 'I' ? 'person' : 'organization'
        entity_id = generate_entity_id(code, supp_id.to_s)

        {
          '@id' => entity_id,
          '@type' => entity_type == 'person' ? 'PersonEntity' : 'OrganizationEntity',
          'entityType' => entity_type,
          'names' => [{
            '@type' => 'NameVariant',
            'fullName' => firm['SUPP_NAME'],
            'isPrimary' => true
          }],
          'addresses' => extract_address(firm),
          'sourceReferences' => [{
            '@type' => 'SourceReference',
            'sourceCode' => 'wb',
            'referenceNumber' => supp_id.to_s
          }]
        }.compact
      end

      # Extract address from firm data
      # @param firm [Hash]
      # @return [Array<Hash>]
      def extract_address(firm)
        addr = {
          '@type' => 'Address',
          'street' => firm['SUPP_ADDR'],
          'city' => firm['SUPP_CITY'],
          'state' => firm['SUPP_STATE_CODE'] || firm['SUPP_PROV_NAME'],
          'country' => firm['COUNTRY_NAME'],
          'countryIsoCode' => firm['LAND1'],
          'postalCode' => firm['SUPP_ZIP_CODE'] || firm['SUPP_POST_CODE']
        }.compact

        addr.empty? ? [] : [addr]
      end

      # Extract a sanction entry
      # @param firm [Hash]
      # @return [Hash, nil]
      def extract_entry(firm)
        supp_id = firm['SUPP_ID']
        return nil unless supp_id

        entity_id = generate_entity_id(code, supp_id.to_s)
        entry_id = generate_entry_id(code, supp_id.to_s)

        # Determine status
        status = map_eligibility_status(firm['SUPP_ELIG_STAT'])

        # Determine debarment type
        debar_type = map_debarment_type(firm['DEBAR_TYPE'])

        {
          '@id' => entry_id,
          '@type' => 'SanctionEntry',
          'entityId' => entity_id,
          'authority' => {
            '@type' => 'Authority',
            'id' => 'wb',
            'name' => 'World Bank',
            'countryCode' => 'WB'
          },
          'referenceNumber' => supp_id.to_s,
          'status' => status,
          'regime' => {
            '@type' => 'SanctionRegime',
            'code' => 'DEBARMENT',
            'name' => 'World Bank Debarment'
          },
          'effects' => [{
            '@type' => 'SanctionEffect',
            'effectType' => 'debarment',
            'scope' => 'full',
            'description' => 'Excluded from World Bank-financed contracts'
          }],
          'period' => {
            '@type' => 'TemporalPeriod',
            'effectiveDate' => firm['DEBAR_FROM_DATE'],
            'expiryDate' => firm['DEBAR_TO_DATE']
          },
          'remarks' => firm['DEBAR_REASON'],
          'rawSourceData' => {
            '@type' => 'RawSourceData',
            'sourceFormat' => 'json',
            'sourceSpecificFields' => {
              'wb:suppTypeCode' => firm['SUPP_TYPE_CODE'],
              'wb:debarType' => firm['DEBAR_TYPE'],
              'wb:debarTypeDesc' => debar_type,
              'wb:crossDebarment' => firm['CRPD_MATCH'],
              'wb:eligStatus' => firm['SUPP_ELIG_STAT'],
              'wb:ineligiblyStatus' => firm['INELIGIBLY_STATUS']
            }.compact
          }
        }
      end

      # Map eligibility status to sanction status
      # @param status [String]
      # @return [String]
      def map_eligibility_status(status)
        case status
        when 'E' then 'active'
        when 'R' then 'resumed'
        when 'S' then 'suspended'
        when 'T' then 'terminated'
        when 'D' then 'delisted'
        else 'active'
        end
      end

      # Map debarment type to description
      # @param type [String]
      # @return [String]
      def map_debarment_type(type)
        case type
        when 'D' then 'Debarred'
        when 'C' then 'Conditional Non-Debarment'
        when 'R' then 'Reinstated'
        else type
        end
      end
    end
  end
end

# Register the extractor
Ammitto::Extractors::Registry.register(:wb, Ammitto::Extractors::WbExtractor)
