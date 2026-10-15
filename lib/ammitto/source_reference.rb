# frozen_string_literal: true

require_relative 'ontology/contracts'
require_relative 'ontology/value_objects/source_reference'

module Ammitto
  # SourceReference represents a reference to an external source
  #
  # Used to track where entity information came from.
  #
  # Legacy facade: its fields are projected from
  # Ontology::ValueObjects::SourceReference (see Ontology::Contracts);
  # +retrieved_at+ is the canonical +fetched_at+.
  #
  # @example Creating a source reference
  #   SourceReference.new(
  #     source_code: :eu,
  #     reference_number: "EU.1234",
  #     url: "https://..."
  #   )
  #
  class SourceReference < Lutaml::Model::Serializable
    Ontology::Contracts.declare_legacy_attributes(self)

    json do
      map 'sourceCode', to: :source_code
      map 'referenceNumber', to: :reference_number
      map 'url', to: :url
      map 'retrievedAt', to: :retrieved_at
      map 'resolution', to: :resolution
    end
  end
end
