# frozen_string_literal: true

require_relative 'base_extractor'
require_relative 'registry'

module Ammitto
  module Extractors
    # NzExtractor extracts sanctions data from New Zealand (MFAT)
    #
    # New Zealand maintains Russia sanctions under the Russia Sanctions Act 2022.
    # Source: https://www.mfat.govt.nz/en/trade-and-country-services/sanctions/
    #
    # Note: NZ also implements UN sanctions, but those are covered by the UN source.
    #
    class NzExtractor < BaseExtractor
      attr_accessor :verbose

      # URL for Russia Sanctions Register (XLSX)
      RUSSIA_SANCTIONS_URL = 'https://www.mfat.govt.nz/assets/Countries-and-Regions/Europe/Ukraine/Russia-Sanctions-Register.xlsx'

      # @return [Symbol] the source code
      def code
        :nz
      end

      # @return [String] authority name
      def authority_name
        'New Zealand (MFAT)'
      end

      # @return [String] primary API endpoint
      def api_endpoint
        RUSSIA_SANCTIONS_URL
      end

      # Fetch raw data from New Zealand (XLSX format)
      # @return [String] path to downloaded XLSX temp file
      def fetch
        require 'open-uri'
        require 'tempfile'

        puts "[#{code}] Downloading XLSX from: #{api_endpoint}" if verbose

        # Download XLSX to temp file
        @temp_file = Tempfile.new(['nz_sanctions', '.xlsx'])
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

      # Extract entities from NZ XLSX
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
Ammitto::Extractors::Registry.register(:nz, Ammitto::Extractors::NzExtractor)
