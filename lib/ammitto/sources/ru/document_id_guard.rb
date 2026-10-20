# frozen_string_literal: true

require 'digest'
require_relative '../../error'
require_relative '../../utils/iri_sanitizer'

module Ammitto
  module Sources
    module Ru
      # Identifies an announcement by its official number, or by its
      # official MID page when that page has no document number. URL
      # identity is internal; it never supplies official document metadata.
      module DocumentIdGuard
        # Room the document id may take in a party reference. A party's
        # reference is "<document>-<name slug, up to 31>-<8-hex digest>",
        # and the IRI builder cuts at 64, so a longer document id would cut
        # off the digest that keeps parties apart.
        DOCUMENT_ID_ROOM = 23

        OFFICIAL_MID_PAGE = %r{\Ahttps://(?:www\.)?mid\.ru/(ru|en)/detail-material-page/([1-9]\d*)/?\z}

        # The same reference must identify the announcement, its group,
        # and its parties. Missing numbers may use a verified URL shape;
        # a nonblank but corrupt number still requires correction upstream.
        # @param block [AnnouncementBlock, nil]
        # @return [String]
        def announcement_reference(block)
          raw_id = block&.document_id
          id = Utils::IriSanitizer.sanitize(raw_id)
          return document_reference(raw_id) unless id == Utils::IriSanitizer::DEFAULT_ID

          reference = official_page_reference(block&.url) if raw_id.to_s.strip.empty?
          return reference if reference

          raise Ammitto::ParseError.new(
            'ru announcement has no usable document_id ' \
            "(#{raw_id.inspect}) or official MID page identity",
            format: :yaml
          )
        end

        # Keep enough room for the party suffix, including its own digest.
        # The page's URL identifies it across updates and party reordering.
        # @param url [String, nil]
        # @return [String, nil]
        def official_page_reference(url)
          page = OFFICIAL_MID_PAGE.match(url.to_s)
          return unless page

          canonical = "https://mid.ru/#{page[1]}/detail-material-page/#{page[2]}"
          "url-#{Digest::SHA256.hexdigest(canonical)[0, DOCUMENT_ID_ROOM - 4]}"
        end

        # The document id as every IRI this announcement mints uses it:
        # sanitized, and when too long, its head plus a digest of the raw
        # id, so ids sharing a long prefix stay apart and a party
        # reference leaves room for its own digest.
        # @param document_id [String] a guarded document id
        # @return [String]
        def document_reference(document_id)
          id = Utils::IriSanitizer.sanitize(document_id)
          return id if id.length <= DOCUMENT_ID_ROOM

          digest = Digest::SHA256.hexdigest(document_id.to_s)[0, 8]
          "#{id[0, DOCUMENT_ID_ROOM - 9]}-#{digest}"
        end

        # @param announcement [Announcement] the parsed announcement
        # @raise [Ammitto::ParseError] when neither the number nor an
        #   official page can identify the announcement
        # @return [void]
        def refuse_without_document_id(announcement)
          announcement_reference(announcement.announcement)
        end
      end
    end
  end
end
