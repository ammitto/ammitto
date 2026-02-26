# frozen_string_literal: true

module Ammitto
  # SanctionReason represents the reason for a sanction
  #
  # Documents why an entity was sanctioned.
  #
  # @example Creating a sanction reason
  #   SanctionReason.new(
  #     category: "proliferation",
  #     description: "Involved in nuclear proliferation activities"
  #   )
  #
  class SanctionReason < Lutaml::Model::Serializable
    # Categories of sanctions reasons
    CATEGORIES = %w[
      terrorism
      proliferation
      human_rights_violations
      corruption
      cyber_activities
      election_interference
      aggression
      procurement_violation
      money_laundering
      drug_trafficking
      transnational_organized_crime
      destabilizing_activity
      sanctions_evasion
      national_security
    ].freeze

    attribute :category, :string           # Category of reason
    attribute :description, :string        # Detailed description
    attribute :cited_provisions, :string, collection: true # Legal provisions cited

    json do
      map 'category', to: :category
      map 'description', to: :description
      map 'citedProvisions', to: :cited_provisions
    end

    # @return [String] display string
    def to_s
      category&.humanize
    end
  end
end
