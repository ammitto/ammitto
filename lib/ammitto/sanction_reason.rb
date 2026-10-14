# frozen_string_literal: true

require 'lutaml/model'
require_relative 'ontology/contracts'
require_relative 'ontology/value_objects/localized_string'
require_relative 'ontology/sanction/sanction_reason'

module Ammitto
  # SanctionReason represents the reason for a sanction
  #
  # Documents why an entity was sanctioned.
  #
  # Legacy facade: its fields are projected from
  # Ontology::Sanction::SanctionReason (see Ontology::Contracts). Here
  # +description+ is the LocalizedString collection (canonical
  # +localized_descriptions+); the canonical scalar is +description_text+.
  #
  # @example Creating a sanction reason
  #   SanctionReason.new(
  #     category: "terrorism",
  #     description: [
  #       LocalizedString.new(value: "参与恐怖活动", language: "zh", script: "Hani", is_primary: true),
  #       LocalizedString.new(value: "Engaging in terrorist activities", language: "en", script: "Latn")
  #     ]
  #   )
  #
  class SanctionReason < Lutaml::Model::Serializable
    # Reason categories (normalized)
    CATEGORIES = %w[
      terrorism
      proliferation
      human_rights_violations
      corruption
      aggression
      national_security
      economic_coercion
      interference
      destabilization
      cyber_attack
      espionage
      other
    ].freeze

    Ontology::Contracts.declare_legacy_attributes(self)

    json do
      map 'category', to: :category
      map 'description', to: :description
      map 'cited_provisions', to: :cited_provisions
      map 'description_text', to: :description_text
    end

    # Get description by language
    # @param lang [String] language code (e.g., "zh", "en")
    # @return [String, nil] the description in the requested language
    def description_in(lang)
      desc = description&.find { |d| d.language == lang }
      desc&.value
    end

    # Get Chinese description
    # @return [String, nil]
    def chinese_description
      description_in('zh')
    end

    # Get English description
    # @return [String, nil]
    def english_description
      description_in('en')
    end

    # @return [String] display string
    def to_s
      english_description || chinese_description || category&.humanize || 'Unknown'
    end
  end
end
