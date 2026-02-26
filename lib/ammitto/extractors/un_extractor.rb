# frozen_string_literal: true

require_relative 'base_extractor'
require_relative 'registry'

module Ammitto
  module Extractors
    # UnExtractor extracts sanctions data from the United Nations
    #
    # Source: https://scsanctions.un.org/resources/xml/en/consolidated.xml
    #
    # UN data structure:
    # - CONSOLIDATED_LIST
    #   - INDIVIDUALS/INDIVIDUAL
    #   - ENTITIES/ENTITY
    #
    class UnExtractor < BaseExtractor
      # @return [Symbol] the source code
      def code
        :un
      end

      # @return [String] authority name
      def authority_name
        'United Nations'
      end

      # @return [String] API endpoint
      def api_endpoint
        'https://scsanctions.un.org/resources/xml/en/consolidated.xml'
      end

      # Fetch raw data from UN
      # @return [Nokogiri::XML::Document]
      def fetch
        download_xml(api_endpoint)
      end

      # Extract entities from UN XML
      # @param doc [Nokogiri::XML::Document]
      # @return [Array<Hash>]
      def extract_entities(doc)
        entities = []

        # Extract individuals
        doc.xpath('//INDIVIDUAL').each do |node|
          entity = extract_individual(node)
          entities << entity if entity
        end

        # Extract entities (organizations)
        doc.xpath('//ENTITY').each do |node|
          entity = extract_entity(node)
          entities << entity if entity
        end

        entities
      end

      # Extract sanction entries from UN XML
      # @param doc [Nokogiri::XML::Document]
      # @return [Array<Hash>]
      def extract_entries(doc)
        entries = []

        doc.xpath('//INDIVIDUAL').each do |node|
          entry = extract_entry(node, 'person')
          entries << entry if entry
        end

        doc.xpath('//ENTITY').each do |node|
          entry = extract_entry(node, 'organization')
          entries << entry if entry
        end

        entries
      end

      private

      # Extract an individual
      # @param node [Nokogiri::XML::Element]
      # @return [Hash, nil]
      def extract_individual(node)
        ref_num = node.at_xpath('REFERENCE_NUMBER')&.text
        return nil unless ref_num

        entity_id = generate_entity_id(code, ref_num)

        # Extract names
        names = []
        node.xpath('.//INDIVIDUAL_ALIAS').each do |alias_node|
          name = {
            '@type' => 'NameVariant',
            'fullName' => alias_node.at_xpath('ALIAS_NAME')&.text,
            'isPrimary' => alias_node.at_xpath('QUALITY')&.text == 'Good'
          }
          names << name.compact
        end

        # Extract birth info
        birth_info = []
        node.xpath('.//INDIVIDUAL_DATE_OF_BIRTH').each do |dob|
          date = dob.at_xpath('DATE')&.text
          birth_info << { '@type' => 'BirthInfo', 'date' => date } if date
        end

        # Extract nationalities
        nationalities = node.xpath('.//INDIVIDUAL_NATIONALITY/NATIONALITY').map(&:text).compact

        {
          '@id' => entity_id,
          '@type' => 'PersonEntity',
          'entityType' => 'person',
          'names' => names,
          'birthInfo' => birth_info,
          'nationalities' => nationalities,
          'sourceReferences' => [{
            '@type' => 'SourceReference',
            'sourceCode' => 'un',
            'referenceNumber' => ref_num
          }]
        }.compact
      end

      # Extract an entity (organization)
      # @param node [Nokogiri::XML::Element]
      # @return [Hash, nil]
      def extract_entity(node)
        ref_num = node.at_xpath('REFERENCE_NUMBER')&.text
        return nil unless ref_num

        entity_id = generate_entity_id(code, ref_num)

        # Extract names
        names = []
        node.xpath('.//ENTITY_ALIAS').each do |alias_node|
          name = {
            '@type' => 'NameVariant',
            'fullName' => alias_node.at_xpath('ALIAS_NAME')&.text,
            'isPrimary' => alias_node.at_xpath('QUALITY')&.text == 'Good'
          }
          names << name.compact
        end

        # Extract addresses
        addresses = []
        node.xpath('.//ENTITY_ADDRESS').each do |addr_node|
          addr = {
            '@type' => 'Address',
            'street' => addr_node.at_xpath('STREET')&.text,
            'city' => addr_node.at_xpath('CITY')&.text,
            'country' => addr_node.at_xpath('COUNTRY')&.text
          }
          addresses << addr.compact unless addr.compact.empty?
        end

        {
          '@id' => entity_id,
          '@type' => 'OrganizationEntity',
          'entityType' => 'organization',
          'names' => names,
          'addresses' => addresses,
          'sourceReferences' => [{
            '@type' => 'SourceReference',
            'sourceCode' => 'un',
            'referenceNumber' => ref_num
          }]
        }.compact
      end

      # Extract a sanction entry
      # @param node [Nokogiri::XML::Element]
      # @param entity_type [String] person or organization
      # @return [Hash, nil]
      def extract_entry(node, _entity_type)
        ref_num = node.at_xpath('REFERENCE_NUMBER')&.text
        return nil unless ref_num

        entity_id = generate_entity_id(code, ref_num)
        entry_id = generate_entry_id(code, ref_num)

        list_type = node.at_xpath('UN_LIST_TYPE')&.text
        listed_on = node.at_xpath('LISTED_ON')&.text

        {
          '@id' => entry_id,
          '@type' => 'SanctionEntry',
          'entityId' => entity_id,
          'authority' => {
            '@type' => 'Authority',
            'id' => 'un',
            'name' => 'United Nations',
            'countryCode' => 'UN'
          },
          'referenceNumber' => ref_num,
          'status' => 'active',
          'regime' => {
            '@type' => 'SanctionRegime',
            'name' => list_type,
            'code' => regime_code(list_type)
          },
          'period' => listed_on ? { '@type' => 'TemporalPeriod', 'listedDate' => listed_on } : nil,
          'rawSourceData' => {
            '@type' => 'RawSourceData',
            'sourceFormat' => 'xml',
            'sourceSpecificFields' => {
              'un:dataId' => node.at_xpath('DATAID')&.text,
              'un:listType' => list_type,
              'un:listedOn' => listed_on
            }.compact
          }
        }.compact
      end

      # Map list type to regime code
      # @param name [String]
      # @return [String]
      def regime_code(name)
        return 'UN' unless name

        case name
        when /Al-Qaida/i then 'AQ'
        when /DPRK|Korea/i then 'DPRK'
        when /Iran/i then 'IRAN'
        when /Somalia/i then 'SOMALIA'
        when /Taliban/i then 'TALIBAN'
        else 'UN'
        end
      end
    end
  end
end

# Register the extractor
Ammitto::Extractors::Registry.register(:un, Ammitto::Extractors::UnExtractor)
