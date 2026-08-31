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

      # New OFAC API endpoints (ZIP files containing XML)
      SDN_ZIP_URL = 'https://sanctionslistservice.ofac.treas.gov/api/PublicationPreview/exports/SDN_ADVANCED.ZIP'
      CONSOLIDATED_ZIP_URL = 'https://sanctionslistservice.ofac.treas.gov/api/PublicationPreview/exports/CONS_ADVANCED.ZIP'

      # Legacy URL (fallback)
      LEGACY_SDN_URL = 'https://www.treasury.gov/ofac/downloads/sdn.xml'

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
        SDN_ZIP_URL
      end

      # Fetch raw data from US OFAC
      #
      # Tries the legacy flat XML first because it is the format this
      # extractor's model matches, and falls back to the newer ZIP export.
      #
      # @return [String] raw XML content
      # @raise [Ammitto::Error] when neither endpoint yields XML
      #   (Ammitto::ParseError when the archive arrived and held none)
      def fetch
        require 'open-uri'

        # Use legacy XML URL (simpler format that matches our model)
        report("Downloading SDN list from #{LEGACY_SDN_URL}...")

        URI.open(LEGACY_SDN_URL, 'User-Agent' => USER_AGENT).read
      rescue StandardError => e
        report("Legacy URL failed (#{safe_message(e)}), trying ZIP...")

        fetch_from_zip(e)
      end

      # Clean up temp file.
      #
      # Closes before unlinking, for the reason NzExtractor#cleanup records:
      # Tempfile#unlink removes the pathname but leaves the descriptor open
      # until GC, and on platforms that refuse to unlink an open file it
      # raises — which on the failure path would replace the download error
      # that actually mattered.
      def cleanup
        @temp_file&.close
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

      # The ZIP export, as a method rather than a second rescue clause on
      # #fetch.
      #
      # It used to be inline, followed by a `rescue StandardError` meant to
      # catch it. That clause could never run: a raise from inside a rescue
      # clause is not caught by a sibling rescue on the same body, so every
      # ZIP failure left #fetch as whatever raw exception the download or
      # the archive produced, and stranded the temp file. Its recovery was
      # also circular — it retried LEGACY_SDN_URL, the URL whose failure is
      # the only way to reach this code at all.
      #
      # @param legacy_error [StandardError] why the legacy URL was abandoned
      # @return [String] raw XML content
      # @raise [Ammitto::ParseError] when the archive holds no XML
      # @raise [Ammitto::Error] when either endpoint failed for another reason
      def fetch_from_zip(legacy_error)
        require 'tempfile'
        require 'zip'

        report("Downloading SDN list from #{SDN_ZIP_URL}...")

        download_zip
        read_xml_from_zip
      rescue Ammitto::ParseError => e
        # Split from the clause below rather than folded into it. The two
        # clauses match different classes and neither depends on the other
        # running, so this is not the sibling-rescue trap the comment above
        # describes -- ParseError is listed first because it is a subclass
        # of Ammitto::Error and Ruby takes the first clause that matches.
        #
        # A ZIP that downloaded intact and carries no XML is unusable
        # content, which is what CnExtractor calls ParseError at
        # cn_extractor.rb:104. Reporting it as a generic failure would tell
        # an operator to retry a fetch that will keep succeeding.
        raise Ammitto::ParseError.new(
          both_endpoints_failed(legacy_error, e), format: :zip
        )
      rescue StandardError => e
        # Generic Ammitto::Error for the reason CnExtractor records at
        # cn_extractor.rb:95: the causes here cannot be told apart. The
        # legacy failure came through `rescue StandardError` and may be
        # anything, and this one is whatever the download raised. Calling a
        # mixed set "network" tells the caller to retry when OFAC may
        # simply have changed what it ships.
        raise Ammitto::Error, both_endpoints_failed(legacy_error, e)
      ensure
        # Both paths, because nothing downstream disposes of this one.
        # FetchCommand#cleanup_extractor is reached only from #parse_xlsx
        # and #parse_pdf; us is an XML source and takes the `else` branch
        # of the format dispatch, which hands back a String and never calls
        # cleanup. The archive is finished with either way — the success
        # path has already read its bytes into memory.
        dispose_archive
      end

      # Both attempts, in one sentence. An operator reading a red harvest
      # cannot act on a message that names only the endpoint that happened
      # to fail last.
      #
      # @param legacy_error [StandardError] why the legacy URL was abandoned
      # @param zip_error [StandardError] why the ZIP export did not answer
      # @return [String]
      def both_endpoints_failed(legacy_error, zip_error)
        'us: neither OFAC endpoint yielded XML — legacy ' \
          "(#{safe_message(legacy_error)}); " \
          "ZIP export (#{safe_message(zip_error)})"
      end

      # Disposal must never become the reported failure, so this swallows
      # its own error rather than replacing the endpoint failure above —
      # the same contract NzExtractor#fetch keeps.
      #
      # @return [void]
      def dispose_archive
        cleanup
      rescue StandardError => e
        complain("could not dispose the ZIP archive: #{safe_message(e)}")
      end

      # An exception's own message, for a message that must not raise.
      #
      # `#message` is evaluated by the interpolation BEFORE #report or
      # #complain is entered, so their rescue clauses never see it: an
      # exception whose message formatter raises escaped #fetch and took
      # the ZIP fallback with it, measured as NoMethodError leaving the
      # method. The class name is kept in the fallback because that is the
      # part an operator can still act on.
      #
      # @param error [Exception]
      # @return [String]
      def safe_message(error)
        error.message.to_s
      rescue StandardError
        "#{safe_class_name(error)} (message unavailable)"
      end

      # The fallback's own fallback. Interpolating `error.class` is not
      # free either — a class whose #to_s raises puts the guard back in the
      # position it exists to prevent — and this is the last interpolation
      # in the chain, so it has to end somewhere that cannot raise.
      #
      # @param error [Exception]
      # @return [String]
      def safe_class_name(error)
        error.class.to_s
      rescue StandardError
        'unknown error'
      end

      # Verbose progress, on a stream that may not accept it.
      #
      # Every caller of this and of #complain is inside a rescue clause, and
      # a raise from inside a rescue clause is not caught by a sibling
      # clause on the same body — the exact shape this file exists to fix.
      # `puts` and `warn` both raise IOError when the embedding process has
      # closed or redirected the stream, so an unguarded log line on the
      # failure path could swallow the ZIP fallback whole: measured, with
      # $stdout closed, as IOError escaping #fetch before #fetch_from_zip
      # was ever called.
      #
      # @param message [String] progress line, without the source prefix
      # @return [void]
      def report(message)
        return unless verbose

        puts "[#{code}] #{message}"
      rescue StandardError
        nil
      end

      # The stderr twin of #report, for a failure worth mentioning even
      # when the operator did not ask for progress.
      #
      # @param message [String] the line, without the source prefix
      # @return [void]
      def complain(message)
        warn "[#{code}] #{message}"
      rescue StandardError
        nil
      end

      # @return [void]
      def download_zip
        @temp_file = Tempfile.new(['us_sdn', '.zip'])
        # Binary, as NzExtractor and UnVesselsExtractor already do for
        # their downloads. A Tempfile opened in text mode expands every
        # 0x0A on Windows, which corrupts the archive: the download
        # succeeds, the ZIP then holds no readable member, and the
        # fallback refuses with "No XML file found in ZIP archive" on
        # Windows alone. Measured on this gem's Windows CI, where all
        # three Ruby versions failed this way and Linux and macOS passed.
        @temp_file.binmode
        URI.open(SDN_ZIP_URL, 'User-Agent' => USER_AGENT) do |remote_file|
          @temp_file.write(remote_file.read)
        end
        @temp_file.close
      end

      # @return [String] the first XML member of the downloaded archive
      # @raise [Ammitto::ParseError] when the archive carries no XML member
      def read_xml_from_zip
        report('Extracting XML from ZIP...')

        Zip::File.open(@temp_file.path) do |zip_file|
          # Find the XML file (usually sdn.xml)
          xml_entry = zip_file.entries.find { |e| e.name =~ /\.xml$/i }
          unless xml_entry
            raise Ammitto::ParseError.new(
              'No XML file found in ZIP archive', format: :zip
            )
          end

          # Block form, because rubyzip closes the entry stream only when
          # given one: rubyzip-2.4.1 lib/zip/entry.rb:577-584 closes in an
          # ensure inside `if block_given?`, and returns the open
          # Zip::InputStream otherwise. Left open, the handle keeps the
          # archive live on Windows and makes the unlink below fail --
          # which is the leak this method is part of fixing.
          xml_entry.get_input_stream(&:read)
        end
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
