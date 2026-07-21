# frozen_string_literal: true

require 'lutaml/model'
require_relative 'localized_string'

module Ammitto
  module Ontology
    module ValueObjects
      # Represents a reference from an announcement to a legal instrument
      #
      # LegalCitation provides structured citation of legal instruments
      # with specific articles, sections, and paragraphs. It supports
      # different citation types (legal basis, reference, amendment).
      #
      # @example Creating a legal citation for China anti-foreign sanctions law
      #   citation = LegalCitation.new(
      #     id: "https://www.ammitto.org/citation/cn/2021-afsla-art4",
      #     legal_instrument_id: "https://www.ammitto.org/instrument/cn/anti-foreign-sanctions-law",
      #     articles: ["第四条", "第五条"],
      #     citation_type: "legal_basis",
      #     context: "Primary legal authority for countermeasures"
      #   )
      #
      # @example Creating a citation with quoted text
      #   citation = LegalCitation.new(
      #     legal_instrument_id: "https://www.ammitto.org/instrument/cn/export-control-law",
      #     articles: ["第十二条"],
      #     citation_type: "reference",
      #     quoted_text: [
      #       LocalizedString.new(value: "国家对管制物项的出口实行许可制度...", language: "zh")
      #     ]
      #   )
      #
      class LegalCitation < Lutaml::Model::Serializable
        # Unique identifier (IRI)
        # @return [String, nil]
        attribute :id, :string

        # Reference to the LegalInstrument being cited
        # @return [String, nil]
        attribute :legal_instrument_id, :string

        # Specific articles cited (e.g., ["第四条", "第五条"])
        # @return [Array<String>, nil]
        attribute :articles, :string, collection: true

        # Specific sections cited
        # @return [Array<String>, nil]
        attribute :sections, :string, collection: true

        # Specific paragraphs cited
        # @return [Array<String>, nil]
        attribute :paragraphs, :string, collection: true

        # Type of citation (legal_basis, reference, amendment, interpretation)
        # @return [String, nil]
        attribute :citation_type, :string

        # Context explaining why this instrument is cited
        # @return [String, nil]
        attribute :context, :string

        # Quoted text from the instrument (in original language)
        # @return [Array<LocalizedString>, nil]
        attribute :quoted_text, LocalizedString, collection: true

        # Check if this is a legal basis citation
        # @return [Boolean]
        def legal_basis?
          citation_type == 'legal_basis'
        end

        # Check if this is an amendment citation
        # @return [Boolean]
        def amendment?
          citation_type == 'amendment'
        end

        # Get a display string for the citation
        # @return [String]
        def display
          parts = []
          parts << "Art. #{articles.join(', ')}" if articles&.any?
          parts << "Sec. #{sections.join(', ')}" if sections&.any?
          parts << "Para. #{paragraphs.join(', ')}" if paragraphs&.any?
          parts.empty? ? legal_instrument_id.to_s : parts.join('; ')
        end

        # Get all cited provisions as a flat array
        # @return [Array<String>]
        def all_provisions
          [articles, sections, paragraphs].flatten.compact
        end

        # Check if citation has any provisions specified
        # @return [Boolean]
        def provisions?
          all_provisions.any?
        end

        key_value do
          map :id, to: :id
          map :legal_instrument_id, to: :legal_instrument_id
          map :articles, to: :articles
          map :sections, to: :sections
          map :paragraphs, to: :paragraphs
          map :citation_type, to: :citation_type
          map :context, to: :context
          map :quoted_text, to: :quoted_text
        end
      end
    end
  end
end
