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
        # One numbered row: the number, an optional "." or ")", then the
        # row's text. data-ru writes party lists as "1        Скотт
        # Моррисон (Scott Morrison)    премьер-министр" in Russian and
        # "1       Scott Morrison, Prime Minister" in English, so neither
        # brackets nor a script can be required; lists elsewhere use
        # "1." and tab-separated columns. ASCII digits only: MID numbers its
        # lists in ASCII, and `String#to_i` would read other digits as 0.
        NUMBERED_ROW = /^[ \t]*(\d+)[.)]?[ \t]+\S/

        # A single numbered line is prose ("1 The committee met"); a list
        # is a run of consecutive numbers from 1. Two rows is the least
        # that is a run.
        MIN_LISTED_ROWS = 2

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
            "parties, but its text carries a numbered list of #{listed}: " \
            'the extraction lost them rather than the announcement naming ' \
            'none',
            format: :yaml
          )
        end

        private

        # Rows of the longest party list in any one language. The same list
        # appears once per translation, so languages are compared rather
        # than added.
        # @param block [AnnouncementBlock, nil] the announcement metadata
        # @return [Integer] 0 when no language carries a list
        def numbered_party_rows(block)
          content = block&.content
          return 0 unless content.is_a?(Hash)

          content.values.map { |text| numbered_run(text.to_s) }.max || 0
        end

        # Length of the longest run 1, 2, 3, ... among the numbered rows
        # of one text, or 0 when that run is shorter than a list.
        # @param text [String] one language's content
        # @return [Integer]
        def numbered_run(text)
          run = 0
          longest = 0
          text.scan(NUMBERED_ROW).each do |(number)|
            number = number.to_i
            # An out-of-order number breaks the run instead of being
            # skipped, so "1, 3, 2" is not read as the list "1, 2".
            run = if number == run + 1 then number
                  elsif number == 1 then 1
                  else 0
                  end
            longest = [longest, run].max
          end
          longest >= MIN_LISTED_ROWS ? longest : 0
        end
      end
    end
  end
end
