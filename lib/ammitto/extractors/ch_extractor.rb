# frozen_string_literal: true

require_relative 'base_extractor'
require_relative 'registry'

module Ammitto
  module Extractors
    # ChExtractor extracts sanctions data from Switzerland (SECO)
    #
    # Source: https://www.sesam.search.admin.ch/sesam-search-web/pages/downloadXmlGesamtliste.xhtml
    # XSD: https://www.seco.admin.ch/dam/seco/en/dokumente/Aussenwirtschaft/Wirtschaftsbeziehungen/Exportkontrollen/Sanktionen/xml_specification_document_xsd_version_6-12-2023.xsd.download.xsd/swiss-sanctions-list_v3.1.xsd
    # Format: XML
    #
    # Note: Swiss server is slow and may require manual download.
    #
    class ChExtractor < BaseExtractor
      attr_accessor :verbose

      # @return [Symbol] the source code
      def code
        :ch
      end

      # @return [String] authority name
      def authority_name
        'Switzerland (SECO)'
      end

      # @return [String] API endpoint
      def api_endpoint
        'https://www.sesam.search.admin.ch/sesam-search-web/pages/downloadXmlGesamtliste.xhtml?lang=en&action=downloadXmlGesamtlisteAction'
      end

      # Fetch raw data from Switzerland
      # @return [String] raw XML content
      def fetch
        # Check for local reference file first
        local_file = find_local_reference_file
        if local_file && File.exist?(local_file)
          puts "[#{code}] Using local reference file: #{local_file}" if verbose
          return File.read(local_file)
        end

        require 'open-uri'

        headers = {
          'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
          'Accept' => 'application/xml, text/xml, */*',
          'Accept-Encoding' => 'gzip, deflate'
        }

        puts "[#{code}] Downloading from #{api_endpoint}..." if verbose

        max_retries = 3
        retry_count = 0

        begin
          timeout_seconds = 600 # 10 minutes

          URI.open(
            api_endpoint,
            headers.merge(
              read_timeout: timeout_seconds,
              open_timeout: 120
            )
          ).read
        rescue Net::ReadTimeout, Net::OpenTimeout, EOFError, Errno::ECONNRESET => e
          retry_count += 1
          raise unless retry_count <= max_retries

          wait_time = retry_count * 30
          if verbose
            puts "[#{code}] Error: #{e.message}, retrying in #{wait_time}s (attempt #{retry_count}/#{max_retries})..."
          end
          sleep(wait_time)
          retry
        end
      end

      # Find local reference file
      # @return [String, nil] path to local file or nil
      def find_local_reference_file
        # Check common locations for local reference files
        base_dir = File.expand_path('../../..', __dir__)
        possible_paths = [
          File.join(base_dir, '..', 'data-ch', 'reference-docs', 'consolidated-list_2026-02-18.xml'),
          File.join(base_dir, '..', 'data-ch', 'reference-docs', 'consolidated-list.xml'),
          File.join(base_dir, 'data-ch', 'reference-docs', 'consolidated-list_2026-02-18.xml'),
          File.join(base_dir, 'data-ch', 'reference-docs', 'consolidated-list.xml')
        ]

        possible_paths.find { |path| File.exist?(path) }
      end

      # Extract entities from Switzerland XML
      # @param doc [Nokogiri::XML::Document]
      # @return [Array<Hash>]
      def extract_entities(doc)
        entities = []

        doc.xpath('//Individual').each do |node|
          entity = extract_individual(node)
          entities << entity if entity
        end

        doc.xpath('//Entity').each do |node|
          entity = extract_organization(node)
          entities << entity if entity
        end

        entities
      end

      # Extract sanction entries from Switzerland XML
      # @param doc [Nokogiri::XML::Document]
      # @return [Array<Hash>]
      def extract_entries(doc)
        entries = []

        doc.xpath('//Individual').each do |node|
          entry = extract_entry(node, 'person')
          entries << entry if entry
        end

        doc.xpath('//Entity').each do |node|
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
        id = node.at_xpath('Id')&.text
        return nil unless id

        entity_id = generate_entity_id(code, id)

        # Extract name
        full_name = node.at_xpath('FullName')&.text

        names = [{
          '@type' => 'NameVariant',
          'fullName' => full_name,
          'isPrimary' => true
        }]

        # Extract aliases
        node.xpath('.//AliasName').each do |alias_node|
          names << {
            '@type' => 'NameVariant',
            'fullName' => alias_node.text,
            'isPrimary' => false
          }
        end

        # Extract birth info
        dob = node.at_xpath('DateOfBirth')&.text
        birth_info = dob ? [{ '@type' => 'BirthInfo', 'date' => dob }] : []

        # Extract addresses
        addresses = node.xpath('.//Address').map do |addr|
          {
            '@type' => 'Address',
            'street' => addr.at_xpath('Street')&.text,
            'city' => addr.at_xpath('City')&.text,
            'country' => addr.at_xpath('Country')&.text,
            'postalCode' => addr.at_xpath('PostalCode')&.text
          }.compact
        end

        # Extract identifications
        identifications = node.xpath('.//Identification').map do |id_node|
          {
            '@type' => 'Identification',
            'type' => id_node.at_xpath('Type')&.text,
            'number' => id_node.at_xpath('Number')&.text,
            'issuingCountry' => id_node.at_xpath('Country')&.text
          }.compact
        end

        {
          '@id' => entity_id,
          '@type' => 'PersonEntity',
          'entityType' => 'person',
          'names' => names,
          'birthInfo' => birth_info,
          'addresses' => addresses,
          'identifications' => identifications,
          'sourceReferences' => [{
            '@type' => 'SourceReference',
            'sourceCode' => 'ch',
            'referenceNumber' => id
          }]
        }.compact
      end

      # Extract an organization
      # @param node [Nokogiri::XML::Element]
      # @return [Hash, nil]
      def extract_organization(node)
        id = node.at_xpath('Id')&.text
        return nil unless id

        entity_id = generate_entity_id(code, id)

        # Extract name
        name = node.at_xpath('Name')&.text

        names = [{
          '@type' => 'NameVariant',
          'fullName' => name,
          'isPrimary' => true
        }]

        # Extract addresses
        addresses = node.xpath('.//Address').map do |addr|
          {
            '@type' => 'Address',
            'street' => addr.at_xpath('Street')&.text,
            'city' => addr.at_xpath('City')&.text,
            'country' => addr.at_xpath('Country')&.text
          }.compact
        end

        {
          '@id' => entity_id,
          '@type' => 'OrganizationEntity',
          'entityType' => 'organization',
          'names' => names,
          'addresses' => addresses,
          'sourceReferences' => [{
            '@type' => 'SourceReference',
            'sourceCode' => 'ch',
            'referenceNumber' => id
          }]
        }.compact
      end

      # Extract a sanction entry
      # @param node [Nokogiri::XML::Element]
      # @param entity_type [String]
      # @return [Hash, nil]
      def extract_entry(node, _entity_type)
        id = node.at_xpath('Id')&.text
        return nil unless id

        entity_id = generate_entity_id(code, id)
        entry_id = generate_entry_id(code, id)

        program = node.at_xpath('SanctionsProgram')&.text

        {
          '@id' => entry_id,
          '@type' => 'SanctionEntry',
          'entityId' => entity_id,
          'authority' => {
            '@type' => 'Authority',
            'id' => 'ch',
            'name' => 'Switzerland (SECO)',
            'countryCode' => 'CH'
          },
          'referenceNumber' => id,
          'status' => 'active',
          'regime' => {
            '@type' => 'SanctionRegime',
            'name' => program || 'Switzerland Sanctions',
            'code' => 'CH_SECO'
          },
          'effects' => [{ '@type' => 'SanctionEffect', 'effectType' => 'asset_freeze', 'scope' => 'full' }],
          'rawSourceData' => {
            '@type' => 'RawSourceData',
            'sourceFormat' => 'xml',
            'sourceSpecificFields' => {
              'ch:program' => program
            }.compact
          }
        }
      end
    end
  end
end

# Register the extractor
Ammitto::Extractors::Registry.register(:ch, Ammitto::Extractors::ChExtractor)
