# frozen_string_literal: true

require_relative 'base_extractor'
require_relative 'registry'

module Ammitto
  module Extractors
    # WbExtractor extracts sanctions data from the World Bank (Debarment List)
    #
    # Source: https://www.worldbank.org/en/projects-operations/procurement/debarred-firms
    #
    # The World Bank page contains JSON data embedded in the HTML.
    # Look for 'class="debarredJsonResponse"' to parse the JSON content.
    #
    # World Bank data structure (JSON):
    # - Array of sanctioned firm objects
    #   - SUPP_ID, SUPP_NAME, SUPP_TYPE_CODE
    #   - DEBAR_FROM_DATE, DEBAR_TO_DATE
    #   - DEBAR_REASON, SUPP_ELIG_STAT
    #
    class WbExtractor < BaseExtractor
      attr_accessor :verbose

      # @return [Symbol] the source code
      def code
        :wb
      end

      # @return [String] authority name
      def authority_name
        'World Bank'
      end

      # @return [String] API endpoint (HTML page with embedded JSON)
      def api_endpoint
        'https://www.worldbank.org/en/projects-operations/procurement/debarred-firms'
      end

      # @return [String] JSON API endpoint
      def json_api_endpoint
        'https://apigwext.worldbank.org/dvsvc/v1.0/json/APPLICATION/ADOBE_EXPRNCE_MGR/FIRM/SANCTIONED_FIRM'
      end

      # @return [String] API key (extracted from WB website)
      def api_key
        'z9duUaFUiEUYSHs97CU38fcZO7ipOPvm'
      end

      # Fetch raw data from World Bank JSON API
      # @return [String] raw JSON content
      def fetch
        require 'open-uri'
        require 'json'

        headers = {
          'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
          'Accept' => 'application/json, */*',
          'apikey' => api_key
        }

        puts "[#{code}] Downloading from #{json_api_endpoint}" if verbose?
        URI.open(json_api_endpoint, headers).read

        # Return the raw JSON content - the fetch_command expects a string
      rescue StandardError => e
        puts "[#{code}] Error fetching WB data: #{e.message}" if verbose?
        raise
      end

      # Fetch from HTML page by finding embedded JSON
      # @return [String] raw JSON content
      def fetch_from_html
        require 'open-uri'
        require 'nokogiri'

        headers = {
          'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
          'Accept' => 'text/html, application/xhtml+xml, */*'
        }

        puts "[#{code}] Downloading HTML from #{api_endpoint}" if verbose?
        html_content = URI.open(api_endpoint, headers).read

        # Parse HTML to find embedded JSON
        doc = Nokogiri::HTML(html_content)

        # Look for element with class="debarredJsonResponse"
        json_element = doc.at_css('.debarredJsonResponse')

        if json_element && !json_element['value'].to_s.strip.empty?
          puts "[#{code}] Found debarredJsonResponse element with data" if verbose?
          return json_element['value']
        end

        # Try to find JSON in script content
        doc.css('script').each do |script|
          content = script.text
          next unless content.include?('debarredJsonResponse') || content.include?('SUPP_ID')

          json_match = content.match(/\[\s*\{.*"SUPP_ID".*\}\s*\]/m)
          if json_match
            puts "[#{code}] Found JSON in script tag" if verbose?
            return json_match[0]
          end
        end

        raise 'Could not find JSON data in World Bank page'
      end

      # Fetch and parse as JSON array
      # @return [Array<Hash>]
      def fetch_json
        require 'json'
        content = fetch
        JSON.parse(content)
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
