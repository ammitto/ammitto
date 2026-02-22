# frozen_string_literal: true

module Ammitto
  # SanctionRegime represents a sanctions regime/program
  #
  # A regime is the overall sanctions program under which entries are listed,
  # such as "DPRK", "Russia/Ukraine", "Al-Qaida", etc.
  #
  # @example Creating a sanction regime
  #   SanctionRegime.new(
  #     name: "Democratic People's Republic of Korea",
  #     code: "DPRK",
  #     description: "Sanctions related to North Korea's nuclear program"
  #   )
  #
  class SanctionRegime < Lutaml::Model::Serializable
    attribute :name, :string          # Full regime name
    attribute :code, :string          # Short code (DPRK, RUSSIA, SDGT, etc.)
    attribute :description, :string   # Description of the regime

    json do
      map 'name', to: :name
      map 'code', to: :code
      map 'description', to: :description
    end

    # @return [String] display string
    def to_s
      name
    end
  end
end
