# frozen_string_literal: true

require_relative 'base_extractor'
require_relative 'registry'

module Ammitto
  module Extractors
    # UsExtractor extracts sanctions data from the United States (OFAC)
    #
    # Source: https://ofac.treasury.gov/sanctions-list-service
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

      # The flat SDN list. Named "legacy" by OFAC, but it is the only export
      # this gem can read: SdnList maps root 'sdnList' and SdnEntry maps
      # 'sdnEntry', and those are the elements this file contains.
      #
      # OFAC also publishes SDN_ADVANCED.ZIP. It is NOT a fallback for this
      # one and was removed as such. Measured 2026-09-01 against the live
      # endpoint: the archive is 5.7 MB, expands to a 126 MB
      # SDN_ADVANCED.XML whose root is <Sanctions> with 19,321
      # <DistinctParty> children and ZERO occurrences of <sdnList> or
      # <sdnEntry>. Feeding it to SdnList.from_xml parses for 288 seconds
      # and yields 0 entries. Reading it would need its own model, which is
      # a feature rather than a fallback.
      SDN_URL = 'https://www.treasury.gov/ofac/downloads/sdn.xml'

      # treasury.gov serves 403 to the default Ruby agent
      USER_AGENT = 'Mozilla/5.0'

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
        SDN_URL
      end

      # Fetch raw data from US OFAC
      #
      # @return [String] raw XML content
      # @raise [Ammitto::NetworkError] when the list cannot be downloaded
      def fetch
        require 'open-uri'

        report("Downloading SDN list from #{SDN_URL}...")

        URI.open(SDN_URL, 'User-Agent' => USER_AGENT).read
      rescue StandardError => e
        # Refuses rather than falling back. The ZIP export used to sit here
        # as a second attempt and could never have produced records; see the
        # note on SDN_URL. A fetch that cannot reach its one source is a
        # failure, and saying so is worth more than five minutes spent
        # parsing the wrong schema to zero.
        raise Ammitto::NetworkError.new(
          "us: could not download the SDN list (#{safe_message(e)})",
          url: SDN_URL
        )
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

      # Verbose progress, on a stream that may not accept it.
      #
      # `puts` raises IOError when the embedding process has closed or
      # redirected $stdout. Unguarded, that raise reaches #fetch's rescue
      # and is reported as a download failure, so the operator is told the
      # source is unreachable when the real fault is the log stream. The
      # refusal must name what actually failed.
      #
      # Reads `verbose?`, not the `verbose` accessor: BaseExtractor#verbose?
      # also honours AMMITTO_VERBOSE, and an extractor that ignored the
      # env var would go quiet for an operator who had asked every other
      # source to talk.
      #
      # @param message [String] progress line, without the source prefix
      # @return [void]
      def report(message)
        return unless verbose?

        puts "[#{code}] #{message}"
      rescue StandardError
        nil
      end

      # An exception's own message, for a message that must not raise.
      #
      # #message is evaluated by the interpolation BEFORE the refusal is
      # built, so an exception whose message formatter raises would escape
      # in place of the typed error.
      #
      # @param error [Exception]
      # @return [String]
      def safe_message(error)
        error.message.to_s
      rescue StandardError
        safe_class_name(error)
      end

      # The fallback's own fallback, because interpolating `error.class` is
      # not free either. Terminates in a literal so the chain cannot raise.
      #
      # @param error [Exception]
      # @return [String]
      def safe_class_name(error)
        error.class.to_s
      rescue StandardError
        'unknown error'
      end

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
