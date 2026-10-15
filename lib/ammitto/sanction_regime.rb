# frozen_string_literal: true

require_relative 'ontology/contracts'
require_relative 'ontology/sanction/sanction_regime'

module Ammitto
  # SanctionRegime represents a sanctions regime/program
  #
  # A regime is the overall sanctions program under which entries are listed,
  # such as "DPRK", "Russia/Ukraine", "Al-Qaida", etc.
  #
  # Legacy facade: its fields are projected from
  # Ontology::Sanction::SanctionRegime (see Ontology::Contracts).
  #
  # @example Creating a sanction regime
  #   SanctionRegime.new(
  #     name: "Democratic People's Republic of Korea",
  #     code: "DPRK",
  #     description: "Sanctions related to North Korea's nuclear program"
  #   )
  #
  class SanctionRegime < Lutaml::Model::Serializable
    Ontology::Contracts.declare_legacy_attributes(self)

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
