# frozen_string_literal: true

require_relative 'base_extractor'
require_relative 'registry'

module Ammitto
  module Extractors
    # EuExtractor extracts sanctions data from the European Union
    #
    # Source: https://ec.europa.eu/external_relations/cfsp/sanctions/list/version4/global/global.xml
    #
    # EU data structure:
    # - sanctionsData/sanctionEntity
    #   - subjectType (person/enterprise)
    #   - nameAlias (names)
    #   - birthdate
    #   - citizenship
    #   - address
    #   - regulation (legal basis)
    #
    class EuExtractor < BaseExtractor
      # @return [Symbol] the source code
      def code
        :eu
      end

      # @return [String] authority name
      def authority_name
        'European Union'
      end

      # @return [String] API endpoint
      def api_endpoint
        'https://ec.europa.eu/external_relations/cfsp/sanctions/list/version4/global/global.xml'
      end

      # Fetch raw data from EU
      # @return [Nokogiri::XML::Document]
      def fetch
        download_xml(api_endpoint)
      end

      # Extract entities from EU XML
      # @param doc [Nokogiri::XML::Document]
      # @return [Array<Hash>]
      def extract_entities(doc)
        entities = []

        doc.xpath('//sanctionEntity').each do |node|
          entity = extract_entity(node)
          entities << entity if entity
        end

        entities
      end

      # Extract sanction entries from EU XML
      # @param doc [Nokogiri::XML::Document]
      # @return [Array<Hash>]
      def extract_entries(doc)
        entries = []

        doc.xpath('//sanctionEntity').each do |node|
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
        ref_number = node.attribute('euReferenceNumber')&.value
        return nil unless ref_number

        entity_type = map_entity_type(
          node.xpath('subjectType').first&.attribute('code')&.value || 'organization'
        )

        entity_id = generate_entity_id(code, ref_number)

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
            'sourceCode' => 'eu',
            'referenceNumber' => ref_number
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

        # Birth info
        birth_info = extract_birth_info(node)
        fields['birthInfo'] = [birth_info] if birth_info

        # Nationalities
        nationalities = node.xpath('citizenship').map do |c|
          c.attribute('countryDescription')&.value
        end.compact
        fields['nationalities'] = nationalities unless nationalities.empty?

        # Gender
        gender = node.xpath('nameAlias').first&.attribute('gender')&.value
        fields['gender'] = gender if gender

        # Identifications
        identifications = extract_identifications(node)
        fields['identifications'] = identifications unless identifications.empty?

        # Addresses
        addresses = extract_addresses(node)
        fields['addresses'] = addresses unless addresses.empty?

        fields
      end

      # Extract organization-specific fields
      # @param node [Nokogiri::XML::Element]
      # @return [Hash]
      def extract_organization_fields(node)
        fields = {}

        # Addresses
        addresses = extract_addresses(node)
        fields['addresses'] = addresses unless addresses.empty?

        fields
      end

      # Extract names from node
      # @param node [Nokogiri::XML::Element]
      # @return [Array<Hash>]
      def extract_names(node)
        names = []

        node.xpath('nameAlias').each_with_index do |name_node, idx|
          name = {
            '@type' => 'NameVariant',
            'fullName' => name_node.attribute('wholeName')&.value,
            'isPrimary' => idx.zero?
          }

          # Try to split into parts
          whole_name = name_node.attribute('wholeName')&.value.to_s
          parts = whole_name.split(/\s+/)
          if parts.length >= 2
            name['lastName'] = parts.first
            name['firstName'] = parts.last
          end

          names << name.compact
        end

        names
      end

      # Extract birth info from node
      # @param node [Nokogiri::XML::Element]
      # @return [Hash, nil]
      def extract_birth_info(node)
        birthdate_node = node.xpath('birthdate').first
        return nil unless birthdate_node

        birth_info = { '@type' => 'BirthInfo' }

        date = birthdate_node.attribute('birthdate')&.value
        birth_info['date'] = date if date

        circa = birthdate_node.attribute('circa')&.value
        birth_info['circa'] = circa == 'true' if circa

        year = birthdate_node.attribute('year')&.value
        birth_info['year'] = year.to_i if year

        country = birthdate_node.attribute('countryDescription')&.value
        birth_info['country'] = country if country

        city = birthdate_node.attribute('city')&.value
        birth_info['city'] = city if city

        birth_info.compact!
        birth_info.empty? ? nil : birth_info
      end

      # Extract identifications from node
      # @param node [Nokogiri::XML::Element]
      # @return [Array<Hash>]
      def extract_identifications(node)
        ids = []

        node.xpath('identification').each do |id_node|
          id = {
            '@type' => 'Identification',
            'type' => id_node.attribute('identificationTypeCode')&.value,
            'number' => id_node.attribute('number')&.value
          }

          country = id_node.attribute('countryIso2Code')&.value
          id['countryIsoCode'] = country if country

          ids << id.compact
        end

        ids
      end

      # Extract addresses from node
      # @param node [Nokogiri::XML::Element]
      # @return [Array<Hash>]
      def extract_addresses(node)
        addresses = []

        node.xpath('address').each do |addr_node|
          addr = { '@type' => 'Address' }

          addr['street'] = addr_node.attribute('street')&.value
          addr['city'] = addr_node.attribute('city')&.value
          addr['state'] = addr_node.attribute('region')&.value
          addr['country'] = addr_node.attribute('countryDescription')&.value
          addr['countryIsoCode'] = addr_node.attribute('countryIso2Code')&.value
          addr['postalCode'] = addr_node.attribute('zipCode')&.value

          addr.compact!
          addresses << addr unless addr.empty?
        end

        addresses
      end

      # Extract a sanction entry
      # @param node [Nokogiri::XML::Element]
      # @return [Hash, nil]
      def extract_entry(node)
        ref_number = node.attribute('euReferenceNumber')&.value
        return nil unless ref_number

        entity_id = generate_entity_id(code, ref_number)
        entry_id = generate_entry_id(code, ref_number)

        # Extract regulations (legal bases)
        regulations = extract_regulations(node)

        # Extract programme (regime)
        programme = regulations.first&.dig(:programme)

        entry = {
          '@id' => entry_id,
          '@type' => 'SanctionEntry',
          'entityId' => entity_id,
          'authority' => {
            '@type' => 'Authority',
            'id' => 'eu',
            'name' => 'European Union',
            'countryCode' => 'EU'
          },
          'referenceNumber' => ref_number,
          'status' => 'active',
          'legalBases' => regulations.map do |reg|
            {
              '@type' => 'LegalInstrument',
              'type' => 'regulation',
              'identifier' => reg[:number],
              'title' => reg[:title],
              'url' => reg[:url]
            }.compact
          end
        }

        # Add regime if available
        if programme
          entry['regime'] = {
            '@type' => 'SanctionRegime',
            'code' => programme,
            'name' => regime_name(programme)
          }
        end

        # Add raw source data
        entry['rawSourceData'] = {
          '@type' => 'RawSourceData',
          'sourceFormat' => 'xml',
          'sourceSpecificFields' => {
            'eu:logicalId' => node.attribute('logicalId')&.value,
            'eu:unitedNationId' => node.xpath('unitedNationId').first&.text
          }.compact
        }

        entry
      end

      # Extract regulations from node
      # @param node [Nokogiri::XML::Element]
      # @return [Array<Hash>]
      def extract_regulations(node)
        regulations = []

        node.xpath('regulation').each do |reg_node|
          reg = {
            number: reg_node.attribute('number')&.value,
            title: reg_node.attribute('numberTitle')&.value,
            url: reg_node.attribute('publicationUrl')&.value,
            programme: reg_node.attribute('programme')&.value
          }.compact

          regulations << reg unless reg.empty?
        end

        regulations
      end

      # Get regime name from code
      # @param code [String]
      # @return [String]
      def regime_name(code)
        {
          'IRQ' => 'Iraq',
          'DPRK' => "Democratic People's Republic of Korea",
          'IRN' => 'Iran',
          'MYA' => 'Myanmar/Burma',
          'SOM' => 'Somalia',
          'SUD' => 'Sudan',
          'SYR' => 'Syria',
          'ZWE' => 'Zimbabwe',
          'AFG' => 'Afghanistan',
          'BEL' => 'Belarus',
          'CIV' => "Côte d'Ivoire",
          'COD' => 'Democratic Republic of the Congo',
          'GIN' => 'Guinea',
          'GNB' => 'Guinea-Bissau',
          'LBY' => 'Libya',
          'MLI' => 'Mali',
          'MOZ' => 'Mozambique',
          'TLS' => 'Timor-Leste',
          'TUN' => 'Tunisia',
          'YEM' => 'Yemen',
          'RUS' => 'Russia/Ukraine'
        }.fetch(code, code)
      end
    end
  end
end

# Register the extractor
Ammitto::Extractors::Registry.register(:eu, Ammitto::Extractors::EuExtractor)
