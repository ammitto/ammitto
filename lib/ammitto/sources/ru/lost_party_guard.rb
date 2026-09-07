# frozen_string_literal: true

require_relative '../../errors/base_error'

module Ammitto
  module Sources
    module Ru
      # Refuses an announcement whose parties were lost in extraction.
      #
      # Its own file rather than more lines on AnnouncementTransformer:
      # the question it answers -- did this announcement name nobody, or
      # did we fail to read who it named -- is about the source document,
      # not about the harmonized shape the transformer builds.
      module LostPartyGuard
        # A numbered party row, "12  Иван Иванов (Ivan Ivanov) министр".
        # The Latin name in brackets is what distinguishes a party list
        # from prose that happens to be numbered.
        NUMBERED_PARTY_ROW = /^\s*\d+\s+\S[^(\n]*\([^)\n]+\)/

        # An announcement that sanctions nobody, and an announcement whose
        # parties failed to parse, arrive here looking identical:
        # `entities` is empty either way, and everything downstream then
        # publishes a document naming no one. Nothing later in the
        # pipeline can tell the two apart.
        #
        # sources/announcements/20220407.yml is the second kind. Its
        # `sanction_details.entities` is empty while its own `content.ru`
        # enumerates over two hundred people by name and number --
        # Australian ministers and members of parliament, under the
        # sentence "список граждан Австралии, которые отныне являются
        # невъездными в Российскую Федерацию". Publishing that as an
        # announcement against nobody is the same error as inventing a
        # sanction, pointing the other way. The exact figure is left to
        # the refusal message, which counts what this file's own pattern
        # matched rather than what a reader counted once.
        #
        # They are separated by the only evidence available here: a
        # numbered list in the text with nothing parsed out of it. A
        # statement that genuinely names no one carries no such list and
        # passes untouched.
        #
        # Refusing rather than dropping the record is deliberate. `ru` is
        # a pending source; the day it publishes, it must not publish this
        # file's silence as a fact about who is sanctioned.
        #
        # @param announcement [Announcement] the parsed announcement
        # @raise [Ammitto::ParseError] when the text lists parties and the
        #   parse produced none
        # @return [void]
        def refuse_if_parties_were_lost(announcement)
          return unless announcement.entities.empty?

          listed = numbered_party_rows(announcement.announcement)
          return if listed.zero?

          raise Ammitto::ParseError.new(
            "ru announcement #{announcement.document_id.inspect} parsed no " \
            "parties, but its text lists #{listed} of them: the extraction " \
            'lost them rather than the announcement naming none',
            format: :yaml
          )
        end

        private

        # @param block [AnnouncementBlock, nil] the announcement metadata
        # @return [Integer] numbered party rows across every language
        def numbered_party_rows(block)
          content = block&.content
          return 0 unless content.is_a?(Hash)

          content.values.sum do |text|
            text.to_s.scan(NUMBERED_PARTY_ROW).length
          end
        end
      end
    end
  end
end
