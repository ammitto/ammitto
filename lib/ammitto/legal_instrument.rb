# frozen_string_literal: true

require_relative 'ontology/contracts'
require_relative 'ontology/value_objects/legal_instrument'

module Ammitto
  # LegalInstrument represents a legal basis for sanctions
  #
  # Documents the legal instrument (regulation, executive order, law, etc.)
  # that provides the legal basis for a sanction.
  #
  # Legacy facade: its fields are projected from
  # Ontology::ValueObjects::LegalInstrument (see Ontology::Contracts).
  #
  # @example Creating a legal instrument
  #   LegalInstrument.new(
  #     type: "resolution",
  #     identifier: "UNSCR 1718",
  #     title: "United Nations Security Council Resolution 1718 (2006)"
  #   )
  #
  class LegalInstrument < Lutaml::Model::Serializable
    # Types of legal instruments
    TYPES = %w[
      regulation
      executive_order
      law
      resolution
      decision
      decree
      directive
      act
      ordinance
      proclamation
      notice
      order
    ].freeze

    Ontology::Contracts.declare_legacy_attributes(self)

    json do
      map 'type', to: :type
      map 'identifier', to: :identifier
      map 'title', to: :title
      map 'issuingBody', to: :issuing_body
      map 'publishDate', to: :publish_date
      map 'url', to: :url
      map 'lang', to: :lang
      map 'effectiveDate', to: :effective_date
      map 'programme', to: :programme
    end

    # @return [String] formatted display string
    def to_s
      [identifier, title].compact.reject(&:empty?).first
    end
  end
end
