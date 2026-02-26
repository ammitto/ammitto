# frozen_string_literal: true

module Ammitto
  module Parsers
    # RuListParser parses the Russia MID sanctions list
    #
    # This parser handles the alphabetical list of sanctioned persons from
    # the Russian Ministry of Foreign Affairs (MID).
    #
    # The format is:
    #   Russian Name
    #   (English Name)
    #   –
    #   Position/Role description
    #
    # @example
    #   parser = Ammitto::Parsers::RuListParser.new(content)
    #   entities = parser.parse
    #   # => [{ name: "John Smith", name_ru: "Джон Смит", position: "...", ... }]
    #
    class RuListParser
      # @return [String] the list content
      attr_reader :content

      # Initialize with list content
      # @param content [String] the markdown/text content
      def initialize(content)
        @content = content
      end

      # Parse the list and extract entities
      # @return [Array<Hash>] array of entity hashes
      def parse
        entities = []

        # Split content into sections (by letter)
        current_letter = nil

        lines = content.lines.map(&:strip)

        i = 0
        while i < lines.length
          line = lines[i]

          # Check for letter header (single letter)
          if line.match?(/^[А-ЯA-Z]$/)
            current_letter = line
            i += 1
            next
          end

          # Try to parse an entry
          entry = parse_entry(lines, i)
          if entry
            entities << entry.merge(
              letter: current_letter,
              source: 'ru',
              list_type: 'entry_ban'
            )
            i = entry[:_lines_consumed] || 1
          else
            i += 1
          end
        end

        entities
      end

      private

      # Parse a single entry starting at the given line index
      # @param lines [Array<String>] all lines
      # @param start_index [Integer] starting index
      # @return [Hash, nil] entity hash or nil if not an entry
      def parse_entry(lines, start_index)
        return nil if start_index >= lines.length

        name_en = nil
        position = nil

        # First line should be Russian name
        first_line = lines[start_index]
        return nil if first_line.nil? || first_line.empty?
        return nil if first_line.match?(/^[А-ЯA-Z]$/) # Letter header
        return nil if first_line.include?('://') # URL
        return nil if first_line.include?('по состоянию на') # Date line

        name_ru = first_line
        lines_consumed = 1

        # Second line might be English name in parentheses
        if start_index + 1 < lines.length
          second_line = lines[start_index + 1]
          if second_line&.match?(/^\(.+\)$/)
            name_en = second_line.gsub(/[()]/, '').strip
            lines_consumed = 2
          end
        end

        # Look for dash and position
        current_idx = start_index + lines_consumed
        while current_idx < lines.length
          line = lines[current_idx]

          # Empty line means end of entry
          break if line.empty?

          # Dash indicates position
          if ['–', '-'].include?(line)
            lines_consumed += 1
            current_idx += 1
            next
          end

          # This should be the position
          if lines_consumed > 1 && ['–', '-'].include?(lines[current_idx - 1])
            position = line
            lines_consumed += 1
            break
          end

          # If we already have position and this isn't empty, this is a new entry
          break if position

          lines_consumed += 1
          current_idx += 1
        end

        return nil unless name_ru || name_en

        {
          id: generate_id(name_en || name_ru),
          name: name_en,
          name_ru: name_ru,
          position: position,
          _lines_consumed: lines_consumed
        }.compact
      end

      # Generate a unique ID for an entity
      # @param name [String]
      # @return [String]
      def generate_id(name)
        slug = name
               .to_s
               .downcase
               .gsub(/[^a-z0-9]+/, '-')
               .gsub(/^-|-$/, '')
               .slice(0, 50)

        "ru-#{slug}"
      end
    end
  end
end
