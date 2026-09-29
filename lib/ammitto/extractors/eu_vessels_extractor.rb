# frozen_string_literal: true

require 'uri'
require_relative 'base_extractor'
require_relative 'registry'

module Ammitto
  module Extractors
    # EuVesselsExtractor extracts EU designated vessels from Danish Maritime Authority
    #
    # Source: INDEX_URL. The workbook link is read from that page on every
    # fetch because DMA publishes each list update under a new Media id and
    # file name, so any stored download URL goes dead at the next update.
    #
    # This list contains vessels designated under Annex XLII of Council Regulation (EU) 833/2014.
    # Note: Vessels can change names, so IMO number is the key identifier.
    #
    class EuVesselsExtractor < BaseExtractor
      attr_accessor :verbose

      # Page that links the current workbook
      INDEX_URL = 'https://www.dma.dk/growth-and-framework-conditions/maritime-sanctions/general-information/eu-vessel-designations'

      USER_AGENT = 'Mozilla/5.0'

      # @return [Symbol] the source code
      def code
        :eu_vessels
      end

      # @return [String] authority name
      def authority_name
        'EU Vessels (via Denmark DMA)'
      end

      # The index page rather than the workbook: callers such as the fetch
      # listing read this without expecting a network request.
      # @return [String] primary API endpoint
      def api_endpoint
        INDEX_URL
      end

      # Fetch raw data (XLSX format)
      # @return [String] path to downloaded XLSX temp file
      def fetch
        url = xlsx_url
        puts "[#{code}] Downloading XLSX from: #{url}" if verbose

        download_binary_to_temp_file(
          url, prefix: 'eu_vessels', ext: '.xlsx',
               headers: { 'User-Agent' => USER_AGENT }
        )
      end

      # The workbook currently linked from INDEX_URL.
      #
      # No fallback to a known URL: a stale workbook would be harvested as
      # if it were current, while a raise stops the scheduled fetch where
      # someone will see it.
      #
      # @return [String] absolute URL of the XLSX
      # @raise [Ammitto::ParseError] unless exactly one workbook is linked
      def xlsx_url
        html = HttpClient.get(INDEX_URL, headers: { 'User-Agent' => USER_AGENT })
        xlsx_url_from(html)
      end

      # Links of any scheme are counted, so a workbook offered only over
      # http or ftp is reported here rather than as HttpClient's https
      # refusal, which would not say where the link came from.
      #
      # @param html [String] the index page
      # @return [String] absolute https URL of the only linked XLSX
      # @raise [Ammitto::ParseError] unless exactly one workbook is linked,
      #   over https
      def xlsx_url_from(html)
        require 'nokogiri'

        urls = Nokogiri::HTML(html).css('a[href]').filter_map do |link|
          url = URI.join(INDEX_URL, link['href'].strip)
          next unless url.path.to_s.downcase.end_with?('.xlsx')

          # A fragment never reaches the server, so it cannot name a second file.
          url.fragment = nil
          url
        rescue URI::Error
          nil
        end.uniq(&:to_s)

        return urls.first.to_s if urls.one? && urls.first.is_a?(URI::HTTPS)

        raise Ammitto::ParseError.new(
          "expected one https .xlsx link on #{INDEX_URL}, found #{urls.length}" \
          "#{": #{urls.join(', ')}" if urls.any?}",
          format: :html
        )
      end

      # Clean up temp file after processing
      def cleanup
        # Closes before unlinking, for the reason NzExtractor#cleanup
        # records: unlink drops the pathname but leaves the descriptor open
        # until GC, and on Windows it raises on an open file — which on the
        # failure path would replace the download error that mattered.
        @temp_file&.close
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
