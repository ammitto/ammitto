# frozen_string_literal: true

module Ammitto
  module Sources
    module Au
      # The Australian sanctions ontology as a whole, how the denormalized
      # CSV maps onto these objects and what the regimes and effects mean,
      # is in lib/ammitto/sources/au.rb.
      # Script enumeration (ISO 15924)
      module Script
        LATN = 'Latn'      # Latin
        ARAB = 'Arab'      # Arabic
        CYRL = 'Cyrl'      # Cyrillic
        HANI = 'Hani'      # Han (Chinese)
        HEBR = 'Hebr'      # Hebrew
        GREK = 'Grek'      # Greek
        DEVA = 'Deva'      # Devanagari
        THAI = 'Thai'      # Thai
        JPAN = 'Jpan'      # Japanese
        KORE = 'Kore'      # Korean

        def self.detect(text)
          return LATN if text.nil? || text.empty?

          case text
          when /[\u0600-\u06FF]/ then ARAB  # Arabic
          when /[\u0400-\u04FF]/ then CYRL  # Cyrillic
          when /[\u4E00-\u9FFF]/ then HANI  # Chinese
          when /[\u0590-\u05FF]/ then HEBR  # Hebrew
          when /[\u0370-\u03FF]/ then GREK  # Greek
          when /[\u0900-\u097F]/ then DEVA  # Devanagari
          when /[\u0E00-\u0E7F]/ then THAI  # Thai
          when /[\u3040-\u309F]/ then JPAN  # Hiragana
          when /[\u30A0-\u30FF]/ then JPAN  # Katakana
          when /[\uAC00-\uD7AF]/ then KORE  # Korean
          else LATN
          end
        end
      end
    end
  end
end
