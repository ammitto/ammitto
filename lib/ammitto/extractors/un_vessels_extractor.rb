# frozen_string_literal: true

require_relative 'base_extractor'
require_relative 'registry'

module Ammitto
  module Extractors
    # UnVesselsExtractor extracts UN Security Council designated vessels
    #
    # Source: https://main.un.org/securitycouncil/en/sanctions/1718
    # PDF: https://main.un.org/securitycouncil/sites/default/files/1718_designated_vessels_list_final.pdf
    # Format: PDF (the committee's only machine-retrievable publication of
    # this list; the materials page links the same file)
    #
    # These vessels are designated under UN Security Council Resolution 1718 (DPRK sanctions)
    # and subsequent resolutions.
    #
    # Note: Vessels frequently change names and flags. IMO number is the key identifier.
    #
    class UnVesselsExtractor < BaseExtractor
      attr_accessor :verbose

      # main.un.org rejects requests whose User-Agent does not look like
      # a real browser — 403 even for a bare "Mozilla/5.0" — so the
      # download announces the same full browser string the
      # BaseExtractor download helpers send.
      USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ' \
                   'AppleWebKit/537.36 (KHTML, like Gecko) ' \
                   'Chrome/120.0.0.0 Safari/537.36'

      # 1718 Committee page
      INDEX_URL = 'https://main.un.org/securitycouncil/en/sanctions/1718'

      # Direct PDF URL
      PDF_URL = 'https://main.un.org/securitycouncil/sites/default/files/1718_designated_vessels_list_final.pdf'

      # The PDF currently serves without a redirect, so a short chain
      # covers a relocated file while a longer one means the endpoint
      # changed and needs a human look.
      MAX_REDIRECTS = 3

      # Seconds to wait for the connection to open
      OPEN_TIMEOUT = 30

      # Seconds to wait for the PDF body to arrive
      READ_TIMEOUT = 120

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

      # Fetch raw data (PDF format). A failed download disposes of the
      # just-created temp file before re-raising: a 403 from a UA
      # change is this source's expected failure mode, and it must not
      # strand the file until process exit.
      # @return [String] path to downloaded PDF temp file
      def fetch
        require 'tempfile'

        puts "[#{code}] Downloading PDF from: #{api_endpoint}" if verbose

        @temp_file = Tempfile.new(['un_vessels', '.pdf'])
        begin
          @temp_file.binmode
          @temp_file.write(download(api_endpoint))
          @temp_file.close
        rescue StandardError
          cleanup
          raise
        end

        @temp_file.path
      end

      # Clean up temp file after processing
      def cleanup
        @temp_file&.close
        @temp_file&.unlink
        @temp_file = nil
      end

      # The legacy non-YAML path never reaches FetchCommand#parse_pdf,
      # whose ensure block owns disposal in the YAML pipeline — so
      # this path disposes of its download itself.
      def run
        super
      ensure
        cleanup
      end

      # Extract entities from data
      # @param data [Hash] fetched data
      # @return [Array<Hash>]
      def extract_entities(data)
        return [] unless data

        # The YAML pipeline parses the PDF via
        # Sources::UnVessels::SanctionsList.from_pdf; this legacy path
        # stays empty.
        []
      end

      # Extract sanction entries from data
      # @param data [Hash] fetched data
      # @return [Array<Hash>]
      def extract_entries(data)
        return [] unless data

        []
      end

      private

      # Downloads +url+ with Net::HTTP instead of open-uri (RuboCop
      # Security/Open). Net::HTTP does not follow redirects on its
      # own, so this loop re-issues the request at each Location, up
      # to MAX_REDIRECTS hops. A non-2xx terminal response raises
      # OpenURI::HTTPError — the class the open-uri download raised —
      # so fetch's temp-file disposal path and its callers see an
      # unchanged failure mode.
      #
      # @param url [String] the URL to download
      # @return [String] the response body
      def download(url)
        require 'net/http'
        require 'open-uri' # OpenURI::HTTPError only; no URI.open here

        uri = URI.parse(url)
        MAX_REDIRECTS.times do
          response = request(uri)
          return response.body if response.is_a?(Net::HTTPSuccess)

          unless response.is_a?(Net::HTTPRedirection)
            raise OpenURI::HTTPError.new(
              "#{response.code} #{response.message}", nil
            )
          end

          uri = URI.join(uri.to_s, response['Location'])
        end

        raise "[#{code}] more than #{MAX_REDIRECTS} redirects for #{url}"
      end

      # One GET, redirects not followed — the download loop owns that.
      #
      # @param uri [URI::HTTP] the URI to request
      # @return [Net::HTTPResponse]
      def request(uri)
        Net::HTTP.start(
          uri.host, uri.port,
          use_ssl: uri.scheme == 'https',
          open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT
        ) do |http|
          http.request(Net::HTTP::Get.new(uri, request_headers))
        end
      end

      # @return [Hash] headers for the PDF request
      def request_headers
        {
          'User-Agent' => USER_AGENT,
          'Accept' => 'application/pdf, */*'
        }
      end
    end
  end
end

# Register the extractor
Ammitto::Extractors::Registry.register(:un_vessels, Ammitto::Extractors::UnVesselsExtractor)
