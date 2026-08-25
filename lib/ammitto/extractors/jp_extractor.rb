# frozen_string_literal: true

require_relative 'base_extractor'
require_relative 'registry'

module Ammitto
  module Extractors
    # JpExtractor extracts Japan End-User List from METI
    #
    # Source: https://www.meti.go.jp/policy/anpo/english/law/doc/EndUserListE.html
    #
    # This extractor never read the source. `fetch` refuses, the extract_*
    # methods return [], and #api_endpoint is left to BaseExtractor, which
    # refuses too — there is no endpoint to name. `ammitto fetch jp` stops
    # earlier still, at FetchCommand::NO_FETCH_PATH, so none of it is
    # reached from the CLI.
    #
    # It used to advertise a .pdf URL. METI publishes a spreadsheet behind
    # a revision-stamped URL discovered from the index page, which is what
    # data-jp downloads and converts, so that constant named a document
    # that does not exist.
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

      # @return [Symbol] the source code
      def code
        :jp
      end

      # @return [String] authority name
      def authority_name
        'Japan Ministry of Economy, Trade and Industry (METI)'
      end

      # Refuse rather than describe a source this class cannot read. The
      # hash this used to return said format 'pdf' and
      # requires_manual_conversion, and both were false: the METI list is
      # a spreadsheet and data-jp converts it automatically. A caller that
      # believed it would go looking for a PDF that is not published.
      #
      # @raise [NotImplementedError] always
      def fetch
        raise NotImplementedError,
              'JpExtractor is a placeholder that never read the source. ' \
              'For programmatic access use ' \
              'Ammitto::Data::Japan::Meti::Extractor, which downloads and ' \
              'parses the METI Foreign User List spreadsheet. The ' \
              'country-specific source CLI does not currently reach it.'
      end

      # Extract entities from data
      # @param data [Hash] fetched data
      # @return [Array<Hash>]
      def extract_entities(data)
        return [] unless data

        # Placeholder: this extractor has never parsed the source.
        []
      end

      # Extract sanction entries from data
      # @param data [Hash] fetched data
      # @return [Array<Hash>]
      def extract_entries(data)
        return [] unless data

        # Placeholder: this extractor has never parsed the source.
        []
      end
    end
  end
end

# Register the extractor
Ammitto::Extractors::Registry.register(:jp, Ammitto::Extractors::JpExtractor)
