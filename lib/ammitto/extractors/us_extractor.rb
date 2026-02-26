# frozen_string_literal: true

require_relative 'base_extractor'
require_relative 'registry'

module Ammitto
  module Extractors
    # UsExtractor extracts sanctions data from the United States (OFAC)
    #
    # Source: https://ofac.treasury.gov/sanctions-lists
    #
    # OFAC provides multiple lists:
    # - SDN (Specially Designated Nationals) - primary sanctions list
    # - Consolidated (Non-SDN) - additional sanctions lists
    #
    # US data structure:
    # - sdnList
    #   - sdnEntry
    #     - uid, firstName, lastName, sdnType
    #     - programList/program
    #     - akaList/aka
    #     - addressList/address
    #     - idList/id
    #     - dateOfBirthList/dateOfBirthItem
    #
    class UsExtractor < BaseExtractor
      attr_accessor :verbose

      # New OFAC API endpoints (ZIP files containing XML)
      SDN_ZIP_URL = 'https://sanctionslistservice.ofac.treas.gov/api/PublicationPreview/exports/SDN_ADVANCED.ZIP'
      CONSOLIDATED_ZIP_URL = 'https://sanctionslistservice.ofac.treas.gov/api/PublicationPreview/exports/CONS_ADVANCED.ZIP'

      # Legacy URL (fallback)
      LEGACY_SDN_URL = 'https://www.treasury.gov/ofac/downloads/sdn.xml'

      # @return [Symbol] the source code
      def code
        :us
      end

      # @return [String] authority name
      def authority_name
        'United States (OFAC)'
      end

      # @return [String] API endpoint
      def api_endpoint
        SDN_ZIP_URL
      end

      # Fetch raw data from US OFAC
      # Downloads ZIP, extracts XML, returns XML content
      # @return [String] raw XML content
      def fetch
        require 'open-uri'
        require 'tempfile'
        require 'zip'

        puts "[#{code}] Downloading SDN list from #{SDN_ZIP_URL}..." if verbose

        # Download ZIP file
        @temp_file = Tempfile.new(['us_sdn', '.zip'])
        URI.open(SDN_ZIP_URL, 'User-Agent' => 'Mozilla/5.0') do |remote_file|
          @temp_file.write(remote_file.read)
        end
        @temp_file.close

        puts "[#{code}] Extracting XML from ZIP..." if verbose

        # Extract XML from ZIP
        xml_content = nil
        Zip::File.open(@temp_file.path) do |zip_file|
          # Find the XML file (usually sdn.xml)
          xml_entry = zip_file.entries.find { |e| e.name =~ /\.xml$/i }
          raise 'No XML file found in ZIP archive' unless xml_entry

          xml_content = xml_entry.get_input_stream.read
        end

        xml_content
      rescue StandardError => e
        puts "[#{code}] Error with ZIP download: #{e.message}, trying legacy URL..." if verbose
        # Fallback to legacy URL
        URI.open(LEGACY_SDN_URL, 'User-Agent' => 'Mozilla/5.0').read
      end

      # Clean up temp file
      def cleanup
        @temp_file&.unlink
        @temp_file = nil
      end

      # Extract entities from US XML
      # @param doc [Nokogiri::XML::Document]
      # @return [Array<Hash>]
      def extract_entities(doc)
        entities = []

        doc.xpath('//sdnEntry').each do |node|
          entity = extract_entity(node)
          entities << entity if entity
        end

        entities
      end

      # Extract sanction entries from US XML
      # @param doc [Nokogiri::XML::Document]
      # @return [Array<Hash>]
      def extract_entries(doc)
        entries = []

        doc.xpath('//sdnEntry').each do |node|
          entry = extract_entry(node)
          entries << entry if entry
        end

        entries
      end

      private

      # Extract an entity
      # @param node [Nokogiri::XML::Element]
      # @return [Hash, nil]
      def extract_entity(node)
        uid = node.at_xpath('uid')&.text
        return nil unless uid

        sdn_type = node.at_xpath('sdnType')&.text || 'Entity'
        entity_type = map_entity_type(sdn_type)
        entity_id = generate_entity_id(code, uid)

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
            'sourceCode' => 'us',
            'referenceNumber' => uid
          }]
        }

        # Add type-specific fields
        case entity_type
        when 'person'
          entity.merge!(extract_person_fields(node))
        else
          entity.merge!(extract_organization_fields(node))
        end

        entity
      end

      # Extract names from node
      # @param node [Nokogiri::XML::Element]
      # @return [Array<Hash>]
      def extract_names(node)
        names = []

        # Primary name
        first_name = node.at_xpath('firstName')&.text
        last_name = node.at_xpath('lastName')&.text

        if first_name || last_name
          full_name = [first_name, last_name].compact.join(' ')
          names << {
            '@type' => 'NameVariant',
            'fullName' => full_name,
            'firstName' => first_name,
            'lastName' => last_name,
            'isPrimary' => true
          }
        end

        # Aliases
        node.xpath('.//akaList/aka').each do |aka|
          aka_first = aka.at_xpath('firstName')&.text
          aka_last = aka.at_xpath('lastName')&.text
          aka_full = [aka_first, aka_last].compact.join(' ')

          names << {
            '@type' => 'NameVariant',
            'fullName' => aka_full,
            'firstName' => aka_first,
            'lastName' => aka_last,
            'isPrimary' => false
          }.compact
        end

        names
      end

      # Extract person-specific fields
      # @param node [Nokogiri::XML::Element]
      # @return [Hash]
      def extract_person_fields(node)
        fields = {}

        # Extract dates of birth
        dobs = node.xpath('.//dateOfBirthList/dateOfBirthItem').map do |dob|
          date = dob.at_xpath('dateOfBirth')&.text
          { '@type' => 'BirthInfo', 'date' => date } if date
        end.compact

        fields['birthInfo'] = dobs unless dobs.empty?

        # Extract IDs (passports, etc.)
        ids = node.xpath('.//idList/id').map do |id|
          {
            '@type' => 'Identification',
            'type' => id.at_xpath('idType')&.text,
            'number' => id.at_xpath('idNumber')&.text,
            'issuingCountry' => id.at_xpath('idCountry')&.text
          }.compact
        end

        fields['identifications'] = ids unless ids.empty?

        fields
      end

      # Extract organization-specific fields
      # @param node [Nokogiri::XML::Element]
      # @return [Hash]
      def extract_organization_fields(node)
        fields = {}

        # Extract addresses
        addresses = node.xpath('.//addressList/address').map do |addr|
          {
            '@type' => 'Address',
            'street' => addr.at_xpath('address1')&.text,
            'city' => addr.at_xpath('city')&.text,
            'state' => addr.at_xpath('stateOrProvince')&.text,
            'country' => addr.at_xpath('country')&.text,
            'postalCode' => addr.at_xpath('postalCode')&.text
          }.compact
        end

        fields['addresses'] = addresses unless addresses.empty?

        fields
      end

      # Extract a sanction entry
      # @param node [Nokogiri::XML::Element]
      # @return [Hash, nil]
      def extract_entry(node)
        uid = node.at_xpath('uid')&.text
        return nil unless uid

        entity_id = generate_entity_id(code, uid)
        entry_id = generate_entry_id(code, uid)

        # Extract programs
        programs = node.xpath('.//programList/program').map(&:text)

        # Extract title
        title = node.at_xpath('title')&.text

        # Extract remarks
        remarks = node.at_xpath('remarks')&.text

        {
          '@id' => entry_id,
          '@type' => 'SanctionEntry',
          'entityId' => entity_id,
          'authority' => {
            '@type' => 'Authority',
            'id' => 'us',
            'name' => 'United States (OFAC)',
            'countryCode' => 'US'
          },
          'referenceNumber' => uid,
          'status' => 'active',
          'regime' => {
            '@type' => 'SanctionRegime',
            'code' => programs.first || 'SDN',
            'name' => programs.join(', ')
          },
          'effects' => [{ '@type' => 'SanctionEffect', 'effectType' => 'asset_freeze', 'scope' => 'full' }],
          'rawSourceData' => {
            '@type' => 'RawSourceData',
            'sourceFormat' => 'xml',
            'sourceSpecificFields' => {
              'us:programs' => programs,
              'us:sdnType' => node.at_xpath('sdnType')&.text,
              'us:title' => title,
              'us:remarks' => remarks
            }.compact
          }
        }
      end
    end
  end
end

# Register the extractor
Ammitto::Extractors::Registry.register(:us, Ammitto::Extractors::UsExtractor)
