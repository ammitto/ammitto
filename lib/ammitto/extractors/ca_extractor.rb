# frozen_string_literal: true

require_relative 'base_extractor'
require_relative 'registry'
require_relative '../errors/base_error'

module Ammitto
  module Extractors
    # CaExtractor extracts sanctions data from Canada (SEFO)
    #
    # Source: https://www.international.gc.ca/world-monde/assets/office_docs/international_relations-relations_internationales/sanctions/sema-lmes.xml
    # Format: XML
    #
    class CaExtractor < BaseExtractor
      # @return [Symbol] the source code
      def code
        :ca
      end

      # @return [String] authority name
      def authority_name
        'Canada (SEFO)'
      end

      # @return [String] API endpoint
      def api_endpoint
        'https://www.international.gc.ca/world-monde/assets/office_docs/international_relations-relations_internationales/sanctions/sema-lmes.xml'
      end

      # @return [String] refusal when the JSON-LD path is taken
      NO_JSONLD_PATH = 'ca: this extractor cannot parse sema-lmes.xml. ' \
                       'Canada is read through Sources::Ca::SanctionsList ' \
                       'on the `--format yaml` path, which is what the ' \
                       'data-ca workflow runs. Use that; refusing rather ' \
                       'than reporting zero entities.'

      # Fetch raw data from Canada
      #
      # `download_xml` returns the response body, not a parsed document —
      # the previous `@return [Nokogiri::XML::Document]` was wrong, which
      # is why the extract methods below used to die on `String#xpath`.
      #
      # @return [String] the raw XML body
      def fetch
        download_xml(api_endpoint)
      end

      # Refuse rather than describe a document this class cannot read.
      #
      # These xpaths looked for `//INDIVIDUAL` and `//ENTITY`. sema-lmes.xml
      # is a `<data-set>` of `<record>` elements and has been for as long
      # as this repository has history, so they matched nothing — and were
      # never reached anyway, because `fetch` hands them a String.
      # `ammitto fetch ca` takes the `--format yaml` branch, which parses
      # with the source model; only `--format jsonld` arrives here.
      #
      # @param _doc [String] the raw body, ignored
      # @raise [Ammitto::ParseError] always
      def extract_entities(_doc)
        raise Ammitto::ParseError, NO_JSONLD_PATH
      end

      # @param _doc [String] the raw body, ignored
      # @raise [Ammitto::ParseError] always
      # @see #extract_entities
      def extract_entries(_doc)
        raise Ammitto::ParseError, NO_JSONLD_PATH
      end
    end
  end
end

# Register the extractor
Ammitto::Extractors::Registry.register(:ca, Ammitto::Extractors::CaExtractor)
