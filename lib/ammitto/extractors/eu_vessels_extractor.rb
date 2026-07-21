# frozen_string_literal: true

require_relative 'base_extractor'
require_relative 'registry'

module Ammitto
  module Extractors
    # EuVesselsExtractor extracts EU designated vessels from Danish Maritime Authority
    #
    # Source: https://www.dma.dk/growth-and-framework-conditions/maritime-sanctions/sanctions-against-russia-and-belarus/eu-vessel-designations
    # Direct download: https://www.dma.dk/Media/639016569144709513/ImportversionListOfEUDesignatedVessels181225.xlsx
    #
    # This list contains vessels designated under Annex XLII of Council Regulation (EU) 833/2014.
    # Note: Vessels can change names, so IMO number is the key identifier.
    #
    class EuVesselsExtractor < BaseExtractor
      attr_accessor :verbose

      # Direct URL to XLSX file
      XLSX_URL = 'https://www.dma.dk/Media/639016569144709513/ImportversionListOfEUDesignatedVessels181225.xlsx'

      # Index page for reference
      INDEX_URL = 'https://www.dma.dk/growth-and-framework-conditions/maritime-sanctions/sanctions-against-russia-and-belarus/eu-vessel-designations'

      # @return [Symbol] the source code
      def code
        :eu_vessels
      end

      # @return [String] authority name
      def authority_name
        'EU Vessels (via Denmark DMA)'
      end

      # @return [String] primary API endpoint
      def api_endpoint
        XLSX_URL
      end

      # Fetch raw data (XLSX format)
      # @return [String] path to downloaded XLSX temp file
      def fetch
        require 'open-uri'
        require 'tempfile'

        puts "[#{code}] Downloading XLSX from: #{api_endpoint}" if verbose

        @temp_file = Tempfile.new(['eu_vessels', '.xlsx'])
        URI.open(api_endpoint, 'User-Agent' => 'Mozilla/5.0') do |remote_file|
          @temp_file.write(remote_file.read)
        end
        @temp_file.close

        @temp_file.path
      end

      # Clean up temp file after processing
      def cleanup
        @temp_file&.unlink
        @temp_file = nil
      end

      # Extract entities from XLSX
      # @param data [Hash] fetched data
      # @return [Array<Hash>]
      def extract_entities(data)
        return [] unless data

        data[:entities] || []
      end
    end
  end
end

# Register the extractor
Ammitto::Extractors::Registry.register(:eu_vessels, Ammitto::Extractors::EuVesselsExtractor)
