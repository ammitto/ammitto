# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Ontology
    module ValueObjects
      # Represents text in a specific language with optional script and region
      #
      # LocalizedString provides proper multilingual support for names,
      # descriptions, and other text content across different languages,
      # scripts, and regions.
      #
      # @example Creating a localized string for Chinese text
      #   name = LocalizedString.new(
      #     value: "三菱重工業株式会社",
      #     language: "zh",
      #     script: "Hani",
      #     is_primary: true
      #   )
      #
      # @example Creating an English transliteration
      #   name = LocalizedString.new(
      #     value: "Mitsubishi Heavy Industries, Ltd.",
      #     language: "en",
      #     script: "Latn",
      #     is_transliteration: true,
      #     transliteration_system: "hepburn"
      #   )
      #
      class LocalizedString < Lutaml::Model::Serializable
        # The text content
        # @return [String, nil]
        attribute :value, :string

        # Language code (ISO 639-1)
        # @return [String, nil]
        attribute :language, :string

        # Script code (ISO 15924: Latn, Hani, Cyrl, Arab, Hant, etc.)
        # @return [String, nil]
        attribute :script, :string

        # Region code (ISO 3166-1: CN, TW, HK, etc.)
        # @return [String, nil]
        attribute :region, :string

        # Whether this is the primary/preferred representation
        # @return [Boolean]
        attribute :is_primary, :boolean, default: false

        # Whether this is a transliteration from another script
        # @return [Boolean]
        attribute :is_transliteration, :boolean, default: false

        # Transliteration system used (pinyin, wade-giles, hepburn, etc.)
        # @return [String, nil]
        attribute :transliteration_system, :string

        # Check if this is a primary representation
        # @return [Boolean]
        def primary?
          is_primary == true
        end

        # Check if this is a transliteration
        # @return [Boolean]
        def transliteration?
          is_transliteration == true
        end

        # Check if this is in a non-Latin script
        # @return [Boolean]
        def non_latin?
          !script.nil? && script != '' && script != 'Latn'
        end

        # Get the language tag (e.g., "zh-Hani-CN")
        # @return [String, nil]
        def language_tag
          parts = [language, script, region].compact
          parts.empty? ? nil : parts.join('-')
        end

        # Parse a language tag into components
        # @param tag [String] language tag like "zh-Hans-CN"
        # @return [LocalizedString]
        def self.from_language_tag(tag, value:, is_primary: false)
          parts = tag.to_s.split('-')
          new(
            value: value,
            language: parts[0],
            script: parts[1]&.match?(/^[A-Z]/) ? parts[1] : nil,
            region: parts.last&.match?(/^[A-Z]{2}$/) ? parts.last : nil,
            is_primary: is_primary
          )
        end

        key_value do
          map :value, to: :value
          map :lang, to: :language
          map :script, to: :script
          map :region, to: :region
          map :is_primary, to: :is_primary
          map :is_transliteration, to: :is_transliteration
          map :transliteration_system, to: :transliteration_system
        end
      end
    end
  end
end
