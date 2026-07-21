# frozen_string_literal: true

require_relative 'ontology/value_objects/localized_string'

module Ammitto
  # SanctionEffect represents the effect of a sanction
  #
  # Documents what the sanction does (asset freeze, travel ban, etc.).
  #
  # @example Creating a sanction effect
  #   SanctionEffect.new(
  #     effect_type: "asset_freeze",
  #     scope: "full",
  #     description: [
  #       LocalizedString.new(value: "All assets frozen", language: "en", is_primary: true),
  #       LocalizedString.new(value: "冻结所有资产", language: "zh", script: "Hani")
  #     ]
  #   )
  #
  class SanctionEffect < Lutaml::Model::Serializable
    # Types of sanction effects
    TYPES = %w[
      asset_freeze
      travel_ban
      arms_embargo
      trade_restriction
      financial_restriction
      technology_restriction
      sectoral_sanction
      debarment
      entry_ban
      investment_ban
      import_ban
      export_ban
      service_restriction
      prohibit_export_dual_use_items
      export_license_requirement
      prohibit_transactions
      prohibit_cooperation
      visa_ban
    ].freeze

    # Scopes of effects
    SCOPES = %w[full partial limited].freeze

    attribute :effect_type, :string    # Type of effect
    attribute :scope, :string          # full, partial, limited
    attribute :description, Ontology::ValueObjects::LocalizedString, collection: true # Localized descriptions

    json do
      map 'effectType', to: :effect_type
      map 'scope', to: :scope
      map 'description', to: :description
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
      effect_type&.humanize
    end
  end
end
