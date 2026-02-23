# frozen_string_literal: true

require_relative 'base_extractor'
require_relative 'registry'

module Ammitto
  module Extractors
    # UnVesselsExtractor extracts UN Security Council designated vessels
    #
    # Source: https://main.un.org/securitycouncil/sanctions/1718
    # PDF: https://main.un.org/securitycouncil/sites/default/files/1718_designated_vessels_list_final.pdf
    # Format: PDF (requires manual conversion to structured data)
    #
    # These vessels are designated under UN Security Council Resolution 1718 (DPRK sanctions)
    # and subsequent resolutions.
    #
    # Note: Vessels frequently change names and flags. IMO number is the key identifier.
    #
    class UnVesselsExtractor < BaseExtractor
      attr_accessor :verbose

      # 1718 Committee page
      INDEX_URL = 'https://main.un.org/securitycouncil/sanctions/1718'

      # Direct PDF URL
      PDF_URL = 'https://main.un.org/securitycouncil/sites/default/files/1718_designated_vessels_list_final.pdf'

      # @return [Symbol] the source code
      def code
        :un_vessels
      end

      # @return [String] authority name
      def authority_name
        'UN Security Council 1718 Committee (DPRK Sanctions)'
      end

      # @return [String] primary API endpoint
      def api_endpoint
        PDF_URL
      end

      # Fetch raw data
      # Note: PDF requires manual conversion to structured data
      # @return [Hash] metadata about the source
      def fetch
        puts "[#{code}] Note: UN Designated Vessels List is PDF-based" if verbose
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
Ammitto::Extractors::Registry.register(:un_vessels, Ammitto::Extractors::UnVesselsExtractor)
