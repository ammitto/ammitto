# frozen_string_literal: true

require_relative 'base_extractor'
require_relative 'registry'
require 'mechanize'

module Ammitto
  module Extractors
    # TrExtractor extracts sanctions data from Turkey (Ministry of Treasury and Finance)
    #
    # Turkey has 4 sanction lists under Law No.6415 and Law No.7262:
    #
    # | List | Law | Description | Format | Status |
    # |------|-----|-------------|--------|--------|
    # | A | Article 5, Law No.6415 | UNSC resolutions | DOCX | SKIP (same as UN source) |
    # | B | Article 6, Law No.6415 | Foreign country requests | XLSX | Active |
    # | C | Article 7, Law No.6415 | Domestic freezing decisions | XLSX | Active |
    # | D | Law No.7262, Art 3.A/3.B | WMD proliferation prevention | XLSX | Active |
    #
    # Source: https://ms.hmb.gov.tr/
    # Files are hosted at: https://ms.hmb.gov.tr/uploads/sites/2/YYYY/MM/
    #
    # IMPORTANT: File URLs are dynamic (include timestamps/hashes).
    # Must update KNOWN_FILE_URLS when URLs change.
    #
    class TrExtractor < BaseExtractor
      attr_accessor :verbose

      # Base URL for file uploads
      UPLOAD_BASE = 'https://ms.hmb.gov.tr'

      # Active lists (excluding A - which is UN sanctions already covered by UN source)
      # Updated 2026-02
      ACTIVE_LISTS = %i[b c d].freeze

      # Known file URLs (updated 2026-02)
      # These URLs contain timestamps/hashes and may change when new files are uploaded
      KNOWN_FILE_URLS = {
        # List A skipped - same as UN sanctions
        b: 'https://ms.hmb.gov.tr/uploads/sites/2/2026/01/B-YABANCI-ULKE-TALEPLERINE-ISTINADEN-MALVARLIKLARI-DONDURULANLAR-6415-SAYILI-KANUN-6.-MADDE-972ff13d63fcaf1d.xlsx',
        c: 'https://ms.hmb.gov.tr/uploads/sites/2/2025/12/IC-DONDURMA-KARARI-ILE-MALVARLIKLARI-DONDURULANLAR-_6415-SAYILI-KANUN-7.-MADDE.SON-327c16916ea14780.xlsx',
        d: 'https://ms.hmb.gov.tr/uploads/sites/2/2025/10/D-7262-SAYILI-KANUN-3.A-VE-3.B-MADDELERI-EXCEL-ce85ee0d2c57738a.xlsx'
      }.freeze

      # @return [Symbol] the source code
      def code
        :tr
      end

      # @return [String] authority name
      def authority_name
        'Turkey (Ministry of Treasury and Finance)'
      end

      # @return [String] primary API endpoint (list D - XLSX)
      def api_endpoint
        KNOWN_FILE_URLS[:d]
      end

      # Fetch raw data from Turkey (List D - XLSX format)
      # @return [String] path to downloaded XLSX temp file
      def fetch
        require 'open-uri'
        require 'tempfile'

        # Use the known file URL for list D (XLSX format)
        file_url = KNOWN_FILE_URLS[:d]

        puts "[#{code}] Downloading XLSX from: #{file_url}" if verbose

        # Download XLSX to temp file
        @temp_file = Tempfile.new(['tr_sanctions', '.xlsx'])
        URI.open(file_url, 'User-Agent' => 'Mozilla/5.0') do |remote_file|
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

      # Extract entities from Turkey XLSX
      # @param data [Hash] fetched data
      # @return [Array<Hash>]
      def extract_entities(data)
        return [] unless data

        # This will be handled by the source model
        data[:entities] || []
      end

      # Extract sanction entries from Turkey XLSX
      # @param data [Hash] fetched data
      # @return [Array<Hash>]
      def extract_entries(data)
        return [] unless data

        data[:entries] || []
      end
    end
  end
end

# Register the extractor
Ammitto::Extractors::Registry.register(:tr, Ammitto::Extractors::TrExtractor)
