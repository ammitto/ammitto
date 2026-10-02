# frozen_string_literal: true

require 'digest'
require_relative '../../error'
require_relative '../../utils/iri_sanitizer'

module Ammitto
  module Sources
    module Ru
      # Refuses an announcement whose document id cannot name it.
      #
      # Every IRI an announcement mints starts from its document id. One
      # that is blank, or that sanitizes to the shared fallback (only
      # punctuation, only non-Latin script, or "unknown" itself), would
      # give every such file the same announcement and group, each
      # overwriting the others in the export.
      module DocumentIdGuard
        # Room the document id may take in a party reference. A party's
        # reference is "<document>-<name slug, up to 31>-<8-hex digest>",
        # and the IRI builder cuts at 64, so a longer document id would cut
        # off the digest that keeps parties apart.
        DOCUMENT_ID_ROOM = 23

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
        # @raise [Ammitto::ParseError] when the document id is absent, blank,
        #   or sanitizes to the shared fallback
        # @return [void]
        def refuse_without_document_id(announcement)
          id = Utils::IriSanitizer.sanitize(announcement.document_id)
          return unless id == Utils::IriSanitizer::DEFAULT_ID

          raise Ammitto::ParseError.new(
            'ru announcement has no usable document_id ' \
            "(#{announcement.document_id.inspect}), so it cannot be told " \
            'apart from any other announcement lacking one',
            format: :yaml
          )
        end
      end
    end
  end
end
