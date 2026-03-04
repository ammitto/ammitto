# frozen_string_literal: true

module Ammitto
  # Tonnage represents vessel tonnage measurements
  #
  # @example Creating tonnage info
  #   Tonnage.new(
  #     gross_register_tonnage: 5000,
  #     deadweight_tonnage: 8000
  #   )
  #
  class Tonnage < Lutaml::Model::Serializable
    attribute :gross_register_tonnage, :integer  # GRT
    attribute :gross_tonnage, :integer           # GT
    attribute :deadweight_tonnage, :integer      # DWT
    attribute :net_tonnage, :integer             # NT

    json do
      map 'grossRegisterTonnage', to: :gross_register_tonnage
      map 'grossTonnage', to: :gross_tonnage
      map 'deadweightTonnage', to: :deadweight_tonnage
      map 'netTonnage', to: :net_tonnage
    end

    # @return [Boolean] whether any tonnage is present
    def present?
      [gross_register_tonnage, gross_tonnage, deadweight_tonnage, net_tonnage]
        .any? { |v| v&.positive? }
    end
  end
end
