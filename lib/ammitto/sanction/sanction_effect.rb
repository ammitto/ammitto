# frozen_string_literal: true

module Ammitto
  # SanctionEffect represents the effect of a sanction
  #
  # Documents what the sanction does (asset freeze, travel ban, etc.).
  #
  # @example Creating a sanction effect
  #   SanctionEffect.new(
  #     effect_type: "asset_freeze",
  #     scope: "full",
  #     description: "All assets frozen"
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
    ].freeze

    # Scopes of effects
    SCOPES = %w[full partial limited].freeze

    attribute :effect_type, :string    # Type of effect
    attribute :scope, :string          # full, partial, limited
    attribute :description, :string    # Detailed description

    json do
      map 'effectType', to: :effect_type
      map 'scope', to: :scope
      map 'description', to: :description
    end

    # @return [String] display string
    def to_s
      effect_type&.humanize
    end
  end
end
