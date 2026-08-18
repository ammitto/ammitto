# frozen_string_literal: true

require 'nokogiri'

module Ammitto
  module Scrapers
    module Ru
      # Parses one MID per-country stop-list page into flat entity hashes.
      #
      # The previous route read the ministry's news feed and pulled names
      # out of prose. That never yielded a trustworthy corpus: prose
      # extraction has no way to know when it has missed someone. Each
      # country's stop list is published as a single HTML table at a
      # stable URL, so parse that instead and let the row count be the
      # completeness check.
      #
      # Row shape, verified against archived captures of the US and
      # Canada pages:
      #
      #   <td></td>                          index, always empty
      #   <td>Русское ИМЯ (English Name)</td> both names in one cell
      #   <td>&ndash;</td>                    separator
      #   <td>должность</td>                  position, Russian
      #
      class StopListPage
        # Pages carry alphabetical divider rows (А, Б, В …) spanning the
        # full width. Canada's page has none and the US page has 28, so
        # a fixed skip count is wrong for one of them; detect the span
        # per cell instead.
        DATA_CELLS = 4

        # Names arrive as "Cyrillic (Latin)", but not dependably. The
        # corpus contains a Cyrillic-only entry, an entry whose opening
        # bracket is missing, and one with a nested bracket inside the
        # Latin form.
        #
        # The bracket is the reliable signal and script is only the
        # fallback, because the source mixes homoglyphs: "БАРРАСCО" and
        # "ГОНCАЛЕС" carry a Latin C inside an otherwise Cyrillic
        # surname, and an English form carries a Cyrillic М. Splitting
        # at the first Latin character therefore cuts several names
        # mid-word. Where no bracket survives, split on whole words and
        # weigh each word's script, so one stray letter cannot move the
        # boundary.
        CYRILLIC = /\p{Cyrillic}/
        LATIN = /\p{Latin}/

        # Brackets and dashes belong to the layout around a name, not
        # to the name; strip them from the edges only.
        EDGE_PUNCTUATION = /[()\s,–-]+/

        attr_reader :country_code, :source_url

        # @param html [String] the page's HTML
        # @param country_code [String] ISO code the page belongs to
        # @param source_url [String] URL the HTML came from
        def initialize(html, country_code:, source_url:)
          @doc = Nokogiri::HTML(html)
          @country_code = country_code
          @source_url = source_url
        end

        # A stop-list page carries two h1s: the country's name, then the
        # list's own title. Only the second identifies what the page is,
        # so match across all of them — reading just the first returns
        # "Канада", which says nothing about sanctions.
        SUBJECT = /санкци|стоп-лист|запрет.*въезд/i

        # @return [Array<String>] every heading on the page
        def headings
          @headings ||= @doc.css('h1')
                            .map { |h| normalize(h.text) }
                            .reject(&:empty?)
        end

        # @return [String, nil] the heading that names the page's subject,
        #   falling back to the first so callers can report what arrived
        def heading
          headings.find { |h| h.match?(SUBJECT) } || headings.first
        end

        # @return [Boolean] whether this is really a stop-list page.
        #
        # Presence of a table is not enough: an ordinary country article
        # can carry a four-column table and would be harvested as
        # entities, and a challenge interstitial carries none and would
        # be reported as an empty success. This project has already been
        # bitten by a fetch that stayed green while producing nothing,
        # so require the subject heading and rows together.
        def stop_list?
          headings.any? { |h| h.match?(SUBJECT) } && entity_rows.any?
        end

        # @return [Array<Hash>] one flat hash per sanctioned entity,
        #   shaped for Sources::Ru::SanctionedEntity
        def entities
          entity_rows.filter_map { |row| build_entity(row) }
        end

        private

        # Rows carrying an entity: exactly four cells, none of them
        # spanning. Dividers and layout rows fall away here rather than
        # being subtracted by index.
        #
        # Scoped to one table and to direct-child cells. A page-wide
        # `table tr` sweep would merge a second table into the list and
        # would read a nested table's cells as though they belonged to
        # the outer row, and either way the corruption would be silent.
        def entity_rows
          @entity_rows ||= target_table ? data_rows(target_table) : []
        end

        # The table holding the list is the one with the most rows that
        # look like entities — chosen by measurement rather than by
        # position, since layout tables come and go around the content.
        def target_table
          return @target_table if defined?(@target_table)

          best = @doc.css('table').max_by { |t| data_rows(t).length }
          @target_table = best && data_rows(best).any? ? best : nil
        end

        def data_rows(table)
          table.xpath('./tr|./tbody/tr').select do |tr|
            cells = tr.xpath('./td')
            next false if cells.length != DATA_CELLS
            next false if cells.any? { |c| c['colspan'] || c['rowspan'] }

            true
          end
        end

        def build_entity(row)
          cells = row.css('td').map { |c| normalize(c.text) }
          russian, english = split_names(cells[1])
          return nil if russian.nil? && english.nil?

          {
            'russian_name' => russian,
            'english_name' => english,
            'entity_type' => 'person',
            'list_type' => 'stop_list',
            # Position text on some pages ends in a semicolon because the
            # source renders the list as one sentence per row.
            'title' => cells[3]&.sub(/;\s*\z/, '').then { |t| presence(t) },
            'country' => country_code,
            'source_url' => source_url
          }.compact
        end

        # Partition a name cell into its Cyrillic and Latin halves.
        # Returns [russian, english], either of which may be nil.
        def split_names(cell)
          return [nil, nil] if cell.nil? || cell.empty?

          russian, english = if (idx = cell.index('('))
                               # Everything inside the outermost bracket
                               # is the Latin form, nested brackets and
                               # all: "Orysia (Irene) Sushko" is one name.
                               [cell[0...idx], cell[(idx + 1)..]]
                             else
                               split_by_word_script(cell)
                             end

          [presence(strip_brackets(russian)), presence(strip_brackets(english))]
        end

        # Fallback for cells with no usable bracket. Find the earliest
        # point from which every remaining word is predominantly Latin;
        # everything before it is the Russian form. Judging a whole word
        # rather than a character keeps a homoglyph from splitting a
        # surname down the middle.
        def split_by_word_script(cell)
          words = cell.split
          boundary = words.length
          words.each_index.reverse_each do |i|
            break unless predominantly_latin?(words[i])

            boundary = i
          end

          [words[0...boundary].join(' '), words[boundary..].join(' ')]
        end

        def predominantly_latin?(word)
          latin = word.each_char.count { |c| c.match?(LATIN) }
          cyrillic = word.each_char.count { |c| c.match?(CYRILLIC) }
          latin.positive? && latin > cyrillic
        end

        # Brackets belong to the layout, not to either name. Strip them
        # from the edges only: a bracket inside the Latin form is part
        # of the name as published.
        def strip_brackets(text)
          normalize(text.to_s)
            .sub(/\A#{EDGE_PUNCTUATION}/o, '')
            .sub(/#{EDGE_PUNCTUATION}\z/o, '')
        end

        # A soft hyphen is an invisible line-break hint sitting inside
        # a word, so it must be deleted rather than spaced: spacing it
        # split "Анна­Мария" into two names. A non-breaking
        # space really is a space, and becomes one.
        def normalize(text)
          text.to_s
              .tr(' ', ' ')
              .delete('­')
              .gsub(/\s+/, ' ')
              .strip
        end

        def presence(text)
          text.nil? || text.empty? ? nil : text
        end
      end
    end
  end
end
