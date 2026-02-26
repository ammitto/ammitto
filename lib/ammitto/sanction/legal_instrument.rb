# frozen_string_literal: true

module Ammitto
  # LegalInstrument represents a legal basis for sanctions
  #
  # Documents the legal instrument (regulation, executive order, law, etc.)
  # that provides the legal basis for a sanction.
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

    attribute :type, :string          # Type of instrument
    attribute :identifier, :string    # E.g., "E.O. 14024", "Regulation 269/2014"
    attribute :title, :string         # Full title
    attribute :issuing_body, :string  # Who issued it
    attribute :issuance_date, :date   # When it was issued
    attribute :url, :string           # Link to the instrument

    json do
      map 'type', to: :type
      map 'identifier', to: :identifier
      map 'title', to: :title
      map 'issuingBody', to: :issuing_body
      map 'issuanceDate', to: :issuance_date
      map 'url', to: :url
    end

    # @return [String] formatted display string
    def to_s
      [identifier, title].compact.reject(&:empty?).first
    end
  end
end
