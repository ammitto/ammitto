# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity

require_relative 'base_extractor'
require_relative 'registry'

module Ammitto
  module Extractors
    # UkExtractor extracts sanctions data from the United Kingdom (UK OFSI)
    #
    # Source: https://sanctionslist.fcdo.gov.uk/docs/UK-Sanctions-List.xml
    #
    # UK data structure:
    # - Designations/Designation
    #   - UniqueID (reference number)
    #   - OFSIGroupID
    #   - UNReferenceNumber
    #   - Names/Name
    #   - NonLatinNames
    #   - RegimeName
    #   - IndividualEntityShip (Individual/Entity)
    #   - SanctionsImposedIndicators
    #   - Addresses/Address
    #   - IndividualDetails/Individual (for persons)
    #     - DOBs
    #     - Nationalities
    #     - Positions
    #     - BirthDetails
    #
    class UkExtractor < BaseExtractor
      # @return [Symbol] the source code
      def code
        :uk
      end

      # @return [String] authority name
      def authority_name
        'United Kingdom (OFSI)'
      end

      # @return [String] API endpoint
      def api_endpoint
        'https://sanctionslist.fcdo.gov.uk/docs/UK-Sanctions-List.xml'
      end

      # Fetch raw data from UK
      # @return [Nokogiri::XML::Document]
      def fetch
        download_xml(api_endpoint)
      end

      # Extract entities from UK XML
      # @param doc [Nokogiri::XML::Document]
      # @return [Array<Hash>]
      def extract_entities(doc)
        entities = []

        doc.xpath('//Designation').each do |node|
          entity = extract_entity(node)
          entities << entity if entity
        end

        entities
      end

      # Extract sanction entries from UK XML
      # @param doc [Nokogiri::XML::Document]
      # @return [Array<Hash>]
      def extract_entries(doc)
        entries = []

        doc.xpath('//Designation').each do |node|
          entry = extract_entry(node)
          entries << entry if entry
        end

        entries
      end

      private

      # Extract a single entity
      # @param node [Nokogiri::XML::Element]
      # @return [Hash, nil]
      def extract_entity(node)
        unique_id = node.at_xpath('UniqueID')&.text
        return nil unless unique_id

        entity_type = map_entity_type(
          node.at_xpath('IndividualEntityShip')&.text || 'Entity'
        )

        entity_id = generate_entity_id(code, unique_id)

        # Extract names
        names = extract_names(node)

        # Build entity based on type
        entity = {
          '@id' => entity_id,
          '@type' => entity_type == 'person' ? 'PersonEntity' : 'OrganizationEntity',
          'entityType' => entity_type,
          'names' => names,
          'sourceReferences' => [{
            '@type' => 'SourceReference',
            'sourceCode' => 'uk',
            'referenceNumber' => unique_id
          }]
        }

        # Add type-specific fields
        case entity_type
        when 'person'
          entity.merge!(extract_person_fields(node))
        when 'organization'
          entity.merge!(extract_organization_fields(node))
        end

        entity
      end

      # Extract person-specific fields
      # @param node [Nokogiri::XML::Element]
      # @return [Hash]
      def extract_person_fields(node)
        fields = {}

        individual = node.at_xpath('.//Individual')
        return fields unless individual

        # Extract dates of birth
        dobs = individual.xpath('.//DOB').map do |dob|
          date = dob.text
          next nil if date.include?('dd/mm') # Placeholder date

          { '@type' => 'BirthInfo', 'date' => date }
        end.compact

        fields['birthInfo'] = dobs unless dobs.empty?

        # Extract nationalities
        nationalities = individual.xpath('.//Nationality').map(&:text).compact
        fields['nationalities'] = nationalities unless nationalities.empty?

        # Extract positions/titles
        positions = individual.xpath('.//Position').map(&:text).compact
        fields['functions'] = positions unless positions.empty?

        # Extract birth details
        birth_details = extract_birth_details(individual)
        fields['birthInfo'] ||= []
        fields['birthInfo'] << birth_details if birth_details

        fields
      end

      # Extract birth details from Individual element
      # @param individual [Nokogiri::XML::Element]
      # @return [Hash, nil]
      def extract_birth_details(individual)
        location = individual.at_xpath('.//BirthDetails//Location')
        return nil unless location

        birth_info = { '@type' => 'BirthInfo' }

        town = location.at_xpath('TownOfBirth')&.text
        birth_info['city'] = town if town

        country = location.at_xpath('CountryOfBirth')&.text
        birth_info['country'] = country if country

        birth_info.empty? ? nil : birth_info
      end

      # Extract organization-specific fields
      # @param node [Nokogiri::XML::Element]
      # @return [Hash]
      def extract_organization_fields(node)
        fields = {}

        # Extract addresses
        addresses = extract_addresses(node)
        fields['addresses'] = addresses unless addresses.empty?

        fields
      end

      # Extract names from node
      # @param node [Nokogiri::XML::Element]
      # @return [Array<Hash>]
      def extract_names(node)
        names = []

        # Extract Latin names
        node.xpath('.//Names/Name').each do |name_node|
          name = {
            '@type' => 'NameVariant',
            'fullName' => name_node.at_xpath('Name6')&.text || name_node.at_xpath('Name1')&.text,
            'isPrimary' => name_node.at_xpath('NameType')&.text == 'Primary Name'
          }

          # Try to parse into parts
          whole_name = name_node.at_xpath('Name6')&.text || name_node.at_xpath('Name1')&.text
          if whole_name
            parts = whole_name.to_s.split(/\s+/)
            if parts.length >= 2
              name['lastName'] = parts.last
              name['firstName'] = parts.first
            end
          end

          names << name.compact
        end

        # Extract non-Latin names
        node.xpath('.//NonLatinNames/NonLatinName').each do |name_node|
          name = {
            '@type' => 'NameVariant',
            'fullName' => name_node.at_xpath('NameNonLatinScript')&.text,
            'script' => 'Arab' # Most common non-Latin script in UK list
          }
          names << name.compact
        end

        names
      end

      # Extract addresses from node
      # @param node [Nokogiri::XML::Element]
      # @return [Array<Hash>]
      def extract_addresses(node)
        addresses = []

        node.xpath('.//Addresses/Address').each do |addr_node|
          addr = { '@type' => 'Address' }

          addr['street'] = addr_node.at_xpath('AddressLine1')&.text
          addr['city'] = addr_node.at_xpath('AddressLine5')&.text
          addr['state'] = addr_node.at_xpath('AddressLine6')&.text
          addr['country'] = addr_node.at_xpath('AddressCountry')&.text

          addr.compact!
          addresses << addr unless addr.empty?
        end

        addresses
      end

      # Extract a sanction entry
      # @param node [Nokogiri::XML::Element]
      # @return [Hash, nil]
      def extract_entry(node)
        unique_id = node.at_xpath('UniqueID')&.text
        return nil unless unique_id

        entity_id = generate_entity_id(code, unique_id)
        entry_id = generate_entry_id(code, unique_id)

        # Extract regime
        regime_name_text = node.at_xpath('RegimeName')&.text

        # Extract sanctions imposed indicators
        indicators = extract_sanctions_indicators(node)
        effects = indicators_to_effects(indicators)

        # Extract sanctions text
        sanctions_text = node.at_xpath('SanctionsImposed')&.text

        # Extract statement of reasons
        reasons_text = node.at_xpath('UKStatementofReasons')&.text

        entry = {
          '@id' => entry_id,
          '@type' => 'SanctionEntry',
          'entityId' => entity_id,
          'authority' => {
            '@type' => 'Authority',
            'id' => 'uk',
            'name' => 'United Kingdom',
            'countryCode' => 'GB'
          },
          'referenceNumber' => unique_id,
          'status' => 'active',
          'regime' => {
            '@type' => 'SanctionRegime',
            'name' => regime_name_text,
            'code' => regime_code(regime_name_text)
          }
        }

        # Add effects
        entry['effects'] = effects unless effects.empty?

        # Add reasons
        if reasons_text
          entry['reasons'] = [{
            '@type' => 'SanctionReason',
            'description' => reasons_text.strip
          }]
        end

        # Add period
        date_designated = node.at_xpath('DateDesignated')&.text
        if date_designated
          entry['period'] = {
            '@type' => 'TemporalPeriod',
            'listedDate' => parse_uk_date(date_designated)
          }
        end

        # Add raw source data
        entry['rawSourceData'] = {
          '@type' => 'RawSourceData',
          'sourceFormat' => 'xml',
          'sourceSpecificFields' => {
            'uk:ofsigroupId' => node.at_xpath('OFSIGroupID')&.text,
            'uk:unReferenceNumber' => node.at_xpath('UNReferenceNumber')&.text,
            'uk:designationSource' => node.at_xpath('DesignationSource')&.text,
            'uk:sanctionsImposed' => sanctions_text,
            'uk:otherInformation' => node.at_xpath('OtherInformation')&.text
          }.compact
        }

        entry
      end

      # Extract sanctions imposed indicators
      # @param node [Nokogiri::XML::Element]
      # @return [Hash]
      def extract_sanctions_indicators(node)
        indicators = {}

        node.xpath('.//SanctionsImposedIndicators/*').each do |indicator|
          indicators[indicator.name] = indicator.text == 'true'
        end

        indicators
      end

      # Convert indicators to effects
      # @param indicators [Hash]
      # @return [Array<Hash>]
      def indicators_to_effects(indicators)
        effects = []

        effect_mapping = {
          'AssetFreeze' => { type: 'asset_freeze', scope: 'full' },
          'ArmsEmbargo' => { type: 'arms_embargo', scope: 'full' },
          'TravelBan' => { type: 'travel_ban', scope: 'full' },
          'TargetedArmsEmbargo' => { type: 'arms_embargo', scope: 'targeted' },
          'TrustServicesSanctions' => { type: 'financial_restriction', scope: 'full' },
          'DirectorDisqualificationSanction' => { type: 'debarment', scope: 'full' }
        }

        indicators.each do |name, enabled|
          next unless enabled
          next unless effect_mapping[name]

          effect = {
            '@type' => 'SanctionEffect',
            'effectType' => effect_mapping[name][:type],
            'scope' => effect_mapping[name][:scope]
          }
          effects << effect
        end

        effects
      end

      # Map regime name to code
      # @param name [String]
      # @return [String]
      def regime_code(name)
        return nil unless name

        code = name.dup
        code.gsub!(/[^A-Z0-9]/, ' ')
        code.gsub!(/\s+/, ' ')
        code = code.split.map { |w| w[0] }.join.upcase
        code[0..10] # Limit length
      end

      # Parse UK date format (dd/mm/yyyy)
      # @param date_str [String]
      # @return [String]
      def parse_uk_date(date_str)
        return nil unless date_str

        parts = date_str.split('/')
        return date_str unless parts.length == 3

        # Convert dd/mm/yyyy to yyyy-mm-dd
        "#{parts[2]}-#{parts[1]}-#{parts[0]}"
      end
    end
  end
end

# rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity

# Register the extractor
Ammitto::Extractors::Registry.register(:uk, Ammitto::Extractors::UkExtractor)
