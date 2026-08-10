# frozen_string_literal: true

require_relative 'base_extractor'
require_relative 'http_client'
require_relative 'registry'

module Ammitto
  module Extractors
    # NzExtractor extracts sanctions data from New Zealand (MFAT)
    #
    # New Zealand maintains Russia sanctions under the Russia Sanctions Act 2022.
    # Source: https://www.mfat.govt.nz/en/countries-and-regions/europe/ukraine/russian-invasion-of-ukraine/sanctions/
    #
    # Note: NZ also implements UN sanctions, but those are covered by the UN source.
    #
    class NzExtractor < BaseExtractor
      attr_accessor :verbose

      # URL for Russia Sanctions Register (XLSX)
      RUSSIA_SANCTIONS_URL = 'https://www.mfat.govt.nz/assets/Countries-and-Regions/Europe/Ukraine/Russia-Sanctions-Register.xlsx'

      # MFAT serves the register only to a browser-shaped agent; this is
      # the string the open-uri download sent.
      USER_AGENT = 'Mozilla/5.0'

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
        require 'tempfile'

        puts "[#{code}] Downloading XLSX from: #{api_endpoint}" if verbose

        # Download XLSX to temp file. A failed download disposes of the
        # just-created temp file before re-raising, so a network error
        # cannot strand it until process exit — FetchCommand's ensure
        # block only owns files that reached the parser.
        @temp_file = Tempfile.new(['nz_sanctions', '.xlsx'])
        begin
          @temp_file.binmode
          @temp_file.write(
            HttpClient.get(api_endpoint, headers: { 'User-Agent' => USER_AGENT })
          )
          @temp_file.close
        rescue StandardError
          cleanup
          raise
        end

        @temp_file.path
      end

      # Clean up temp file after processing.
      #
      # Closes before unlinking: Tempfile#unlink removes the pathname
      # but leaves the descriptor open until GC, so unlink-only left a
      # live handle on a file nobody could find — and on platforms that
      # refuse to unlink an open file it raises, which on the failure
      # path would replace the download error that actually mattered.
      def cleanup
        @temp_file&.close
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
