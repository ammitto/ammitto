# frozen_string_literal: true

require_relative 'base_extractor'
require_relative 'registry'

module Ammitto
  module Extractors
    # JpExtractor extracts Japan End-User List from METI
    #
    # Source: https://www.meti.go.jp/policy/anpo/english/law/doc/EndUserListE.html
    # Format: PDF (requires manual conversion to structured data)
    #
    # The End-User List is maintained under Japan's Foreign Exchange and Foreign
    # Trade Act (FEFTA) and related export control regulations.
    #
    # Note: This list is primarily for export control purposes, not financial
    # sanctions. It lists entities that may be involved in WMD proliferation.
    #
    class JpExtractor < BaseExtractor
      attr_accessor :verbose

      # Index page URL
      INDEX_URL = 'https://www.meti.go.jp/policy/anpo/english/law/doc/EndUserListE.html'

      # PDF download URL (this may change - check the index page)
      PDF_URL = 'https://www.meti.go.jp/policy/anpo/english/law/doc/EndUserListE.pdf'

      # @return [Symbol] the source code
      def code
        :jp
      end

      # @return [String] authority name
      def authority_name
        'Japan Ministry of Economy, Trade and Industry (METI)'
      end

      # @return [String] primary API endpoint
      def api_endpoint
        PDF_URL
      end

      # Fetch raw data
      # Note: PDF requires manual conversion to structured data
      # @return [Hash] metadata about the source
      def fetch
        puts "[#{code}] Note: Japan End-User List is PDF-based" if verbose
        puts "[#{code}] Source: #{INDEX_URL}" if verbose

        {
          source: code,
          format: 'pdf',
          index_url: INDEX_URL,
          pdf_url: PDF_URL,
          requires_manual_conversion: true
        }
      end

      # Extract entities from data
      # @param data [Hash] fetched data
      # @return [Array<Hash>]
      def extract_entities(data)
        return [] unless data

        # PDF data requires manual conversion
        # This returns empty until manual conversion is implemented
        []
      end

      # Extract sanction entries from data
      # @param data [Hash] fetched data
      # @return [Array<Hash>]
      def extract_entries(data)
        return [] unless data

        # PDF data requires manual conversion
        []
      end
    end
  end
end

# Register the extractor
Ammitto::Extractors::Registry.register(:jp, Ammitto::Extractors::JpExtractor)
