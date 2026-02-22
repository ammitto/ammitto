# frozen_string_literal: true

module Ammitto
  module Extractors
    # Base extractor provides common interface for all source extractors
    #
    # Each extractor should inherit from this class and implement:
    # - #code: Symbol identifying the source
    # - #authority: Authority information hash
    # - #api_endpoint: URL to fetch raw data
    # - #fetch: Download and parse raw data
    # - #extract_entities: Extract entities from raw data
    # - #extract_entries: Extract sanction entries from raw data
    #
    # @example Creating an extractor
    #   class EuExtractor < BaseExtractor
    #     def code
    #       :eu
    #     end
    #
    #     def extract_entities(raw_data)
    #       # Parse XML and return array of entity hashes
    #     end
    #   end
    #
    class BaseExtractor
      # Get the source code
      # @return [Symbol]
      def code
        raise NotImplementedError, 'Subclasses must implement #code'
      end

      # Get the authority information
      # @return [Hash]
      def authority
        {
          id: code.to_s,
          name: authority_name,
          country_code: code.to_s.upcase
        }
      end

      # Get the authority name
      # @return [String]
      def authority_name
        raise NotImplementedError, 'Subclasses must implement #authority_name'
      end

      # Get the API endpoint URL
      # @return [String]
      def api_endpoint
        raise NotImplementedError, 'Subclasses must implement #api_endpoint'
      end

      # Run the extraction process
      # @return [Hash] extraction results
      def run
        puts "[#{code}] Starting extraction..." if verbose?

        # Fetch raw data
        raw_data = fetch

        # Extract entities and entries
        entities = extract_entities(raw_data)
        entries = extract_entries(raw_data)

        puts "[#{code}] Extracted #{entities.length} entities, #{entries.length} entries" if verbose?

        {
          code: code,
          entities: entities.length,
          entries: entries.length,
          status: :success
        }
      rescue StandardError => e
        puts "[#{code}] ERROR: #{e.message}" if verbose?
        puts e.backtrace.first(5).join("\n") if verbose?
        {
          code: code,
          status: :error,
          error: e.message
        }
      end

      # Fetch raw data from source
      # @return [Object] raw data (XML, JSON, etc.)
      def fetch
        raise NotImplementedError, 'Subclasses must implement #fetch'
      end

      # Extract entities from raw data
      # @param raw_data [Object] the raw data
      # @return [Array<Hash>] array of entity hashes
      def extract_entities(raw_data)
        raise NotImplementedError, 'Subclasses must implement #extract_entities'
      end

      # Extract sanction entries from raw data
      # @param raw_data [Object] the raw data
      # @return [Array<Hash>] array of sanction entry hashes
      def extract_entries(raw_data)
        raise NotImplementedError, 'Subclasses must implement #extract_entries'
      end

      # Generate a stable entity ID
      # @param source_code [Symbol] the source code
      # @param reference_number [String] the reference number
      # @return [String] URI
      def generate_entity_id(source_code, reference_number)
        "https://www.ammitto.org/entity/#{source_code}/#{reference_number}"
      end

      # Generate a stable entry ID
      # @param source_code [Symbol] the source code
      # @param reference_number [String] the reference number
      # @return [String] URI
      def generate_entry_id(source_code, reference_number)
        "https://www.ammitto.org/entry/#{source_code}/#{reference_number}"
      end

      # Map entity type to standard type
      # @param type [String] source-specific type
      # @return [String] standard type (person, organization, vessel, aircraft)
      def map_entity_type(type)
        case type.to_s.downcase
        when /person|individual|human/
          'person'
        when /organization|company|enterprise|corporation|firm/
          'organization'
        when /vessel|ship|boat/
          'vessel'
        when /aircraft|plane|helicopter/
          'aircraft'
        else
          'organization'
        end
      end

      private

      # Check if verbose mode is enabled
      # @return [Boolean]
      def verbose?
        @verbose || ENV['AMMITTO_VERBOSE'] == 'true'
      end

      # Download XML from URL
      # @param url [String] the URL
      # @param headers [Hash] optional HTTP headers
      # @return [Nokogiri::XML::Document] parsed XML
      def download_xml(url, headers = {})
        require 'open-uri'
        require 'nokogiri'

        default_headers = {
          'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept' => 'application/xml, text/xml, */*'
        }

        puts "[#{code}] Downloading from #{url}" if verbose?
        content = URI.open(url, default_headers.merge(headers)).read
        Nokogiri::XML(content)
      end

      # Download JSON from URL
      # @param url [String] the URL
      # @param headers [Hash] optional HTTP headers
      # @return [Hash] parsed JSON
      def download_json(url, headers = {})
        require 'open-uri'
        require 'json'

        default_headers = {
          'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept' => 'application/json, */*'
        }

        puts "[#{code}] Downloading from #{url}" if verbose?
        content = URI.open(url, default_headers.merge(headers)).read
        JSON.parse(content)
      end
    end
  end
end
