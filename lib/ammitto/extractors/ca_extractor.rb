# frozen_string_literal: true

require_relative 'base_extractor'
require_relative 'registry'
require_relative '../errors/base_error'

module Ammitto
  module Extractors
    # CaExtractor extracts sanctions data from Canada (SEFO)
    #
    # Source: https://www.international.gc.ca/world-monde/assets/office_docs/international_relations-relations_internationales/sanctions/sema-lmes.xml
    # Format: XML
    #
    class CaExtractor < BaseExtractor
      # @return [Symbol] the source code
      def code
        :ca
      end

      # @return [String] authority name
      def authority_name
        'Canada (SEFO)'
      end

      # @return [String] API endpoint
      def api_endpoint
        'https://www.international.gc.ca/world-monde/assets/office_docs/international_relations-relations_internationales/sanctions/sema-lmes.xml'
      end

      # @return [String] refusal when the JSON-LD path is taken
      NO_JSONLD_PATH = 'ca: this extractor cannot parse sema-lmes.xml. ' \
                       'Canada is read through Sources::Ca::SanctionsList ' \
                       'on the `--format yaml` path, which is what the ' \
                       'data-ca workflow runs. Use that; refusing rather ' \
                       'than reporting zero entities.'

      # Fetch raw data from Canada
      #
      # `download_xml` returns the response body, not a parsed document —
      # the previous `@return [Nokogiri::XML::Document]` was wrong, which
      # is why the extract methods below used to die on `String#xpath`.
      #
      # @return [String] the raw XML body
      def fetch
        download_xml(api_endpoint)
      end

      # Refuse rather than describe a document this class cannot read.
      #
      # These xpaths looked for `//INDIVIDUAL` and `//ENTITY`. sema-lmes.xml
      # is a `<data-set>` of `<record>` elements and has been for as long
      # as this repository has history, so they matched nothing — and were
      # never reached anyway, because `fetch` hands them a String.
      # `ammitto fetch ca` takes the `--format yaml` branch, which parses
      # with the source model; only `--format jsonld` arrives here.
      #
      # @param _doc [String] the raw body, ignored
      # @raise [Ammitto::ParseError] always
      def extract_entities(_doc)
        raise Ammitto::ParseError, NO_JSONLD_PATH
      end

      # @param _doc [String] the raw body, ignored
      # @raise [Ammitto::ParseError] always
      # @see #extract_entities
      def extract_entries(_doc)
        raise Ammitto::ParseError, NO_JSONLD_PATH
      end

      private

      # Extract an individual
      # @param node [Nokogiri::XML::Element]
      # @return [Hash, nil]
      def extract_individual(node)
        id = node.at_xpath('ID')&.text
        return nil unless id

        entity_id = generate_entity_id(code, id)

        # Extract name
        first_name = node.at_xpath('FIRST_NAME')&.text
        last_name = node.at_xpath('LAST_NAME')&.text
        full_name = [first_name, last_name].compact.join(' ')

        # Extract aliases
        names = [{
          '@type' => 'NameVariant',
          'fullName' => full_name,
          'firstName' => first_name,
          'lastName' => last_name,
          'isPrimary' => true
        }]

        node.xpath('.//ALIAS').each do |alias_node|
          names << {
            '@type' => 'NameVariant',
            'fullName' => alias_node.at_xpath('ALIAS_NAME')&.text,
            'isPrimary' => false
          }
        end

        # Extract birth info
        birth_info = node.xpath('.//DATE_OF_BIRTH').map do |dob|
          { '@type' => 'BirthInfo', 'date' => dob.at_xpath('DATE')&.text }
        end.compact

        # Extract addresses
        addresses = node.xpath('.//ADDRESS').map do |addr|
          {
            '@type' => 'Address',
            'street' => addr.at_xpath('STREET')&.text,
            'city' => addr.at_xpath('CITY')&.text,
            'state' => addr.at_xpath('PROVINCE')&.text,
            'country' => addr.at_xpath('COUNTRY')&.text,
            'postalCode' => addr.at_xpath('POSTAL_CODE')&.text
          }.compact
        end

        {
          '@id' => entity_id,
          '@type' => 'PersonEntity',
          'entityType' => 'person',
          'names' => names,
          'birthInfo' => birth_info,
          'addresses' => addresses,
          'sourceReferences' => [{
            '@type' => 'SourceReference',
            'sourceCode' => 'ca',
            'referenceNumber' => id
          }]
        }.compact
      end

      # Extract an organization
      # @param node [Nokogiri::XML::Element]
      # @return [Hash, nil]
      def extract_organization(node)
        id = node.at_xpath('ID')&.text
        return nil unless id

        entity_id = generate_entity_id(code, id)

        # Extract name
        name = node.at_xpath('NAME')&.text

        # Extract aliases
        names = [{
          '@type' => 'NameVariant',
          'fullName' => name,
          'isPrimary' => true
        }]

        node.xpath('.//ALIAS').each do |alias_node|
          names << {
            '@type' => 'NameVariant',
            'fullName' => alias_node.at_xpath('ALIAS_NAME')&.text,
            'isPrimary' => false
          }
        end

        # Extract addresses
        addresses = node.xpath('.//ADDRESS').map do |addr|
          {
            '@type' => 'Address',
            'street' => addr.at_xpath('STREET')&.text,
            'city' => addr.at_xpath('CITY')&.text,
            'state' => addr.at_xpath('PROVINCE')&.text,
            'country' => addr.at_xpath('COUNTRY')&.text
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
            'sourceCode' => 'ca',
            'referenceNumber' => id
          }]
        }.compact
      end

      # Extract a sanction entry
      # @param node [Nokogiri::XML::Element]
      # @param entity_type [String]
      # @return [Hash, nil]
      def extract_entry(node, _entity_type)
        id = node.at_xpath('ID')&.text
        return nil unless id

        entity_id = generate_entity_id(code, id)
        entry_id = generate_entry_id(code, id)

        program = node.at_xpath('SANCTIONS_PROGRAM')&.text
        schedule = node.at_xpath('SCHEDULE')&.text

        {
          '@id' => entry_id,
          '@type' => 'SanctionEntry',
          'entityId' => entity_id,
          'authority' => {
            '@type' => 'Authority',
            'id' => 'ca',
            'name' => 'Canada (SEFO)',
            'countryCode' => 'CA'
          },
          'referenceNumber' => id,
          'status' => 'active',
          'regime' => {
            '@type' => 'SanctionRegime',
            'name' => program,
            'code' => program_code(program)
          },
          'effects' => [{ '@type' => 'SanctionEffect', 'effectType' => 'asset_freeze', 'scope' => 'full' }],
          'rawSourceData' => {
            '@type' => 'RawSourceData',
            'sourceFormat' => 'xml',
            'sourceSpecificFields' => {
              'ca:program' => program,
              'ca:schedule' => schedule
            }.compact
          }
        }
      end

      # Map program to code
      # @param program [String]
      # @return [String]
      def program_code(program)
        return 'CA' unless program

        case program.upcase
        when /SEMA/ then 'CA_SEMA'
        when /JVCFOA/ then 'CA_JVCFOA'
        when /RUSSIA/ then 'RUSSIA'
        when /IRAN/ then 'IRAN'
        when /DPRK/ then 'DPRK'
        else program.upcase[0..10]
        end
      end
    end
  end
end

# Register the extractor
Ammitto::Extractors::Registry.register(:ca, Ammitto::Extractors::CaExtractor)
