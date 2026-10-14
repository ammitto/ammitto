# frozen_string_literal: true

require_relative 'ontology/contracts'
require_relative 'ontology/value_objects/tonnage'

module Ammitto
  # Tonnage represents vessel tonnage measurements
  #
  # Legacy facade: its fields are projected from
  # Ontology::ValueObjects::Tonnage (see Ontology::Contracts), under the
  # long names (gross_tonnage is the canonical gt, and so on).
  #
  # @example Creating tonnage info
  #   Tonnage.new(
  #     gross_register_tonnage: 5000,
  #     deadweight_tonnage: 8000
  #   )
  #
  class Tonnage < Lutaml::Model::Serializable
    Ontology::Contracts.declare_legacy_attributes(self)

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
