# frozen_string_literal: true

require 'lutaml/model'
require_relative '../types'

module Ammitto
  module Ontology
    module ValueObjects
      # Represents a legal instrument (regulation, decision, law, etc.)
      #
      # Legal instruments are the basis for sanctions. They can be
      # EU regulations, UN resolutions, national laws, etc.
      #
      # @example Creating a legal instrument
      #   instrument = LegalInstrument.new(
      #     type: :regulation,
      #     identifier: "Council Regulation (EU) No 269/2014",
      #     title: "restrictive measures in respect of actions...",
      #     issuing_body: "Council of the European Union",
      #     issuance_date: Date.new(2014, 3, 17),
      #     url: "https://eur-lex.europa.eu/..."
      #   )
      #
      class LegalInstrument < Lutaml::Model::Serializable
        # Type of legal instrument
        # @return [Symbol, String, nil]
        attribute :type, :string

        # Official identifier/number
        # @return [String, nil]
        attribute :identifier, :string

        # Full title of the instrument
        # @return [String, nil]
        attribute :title, :string

        # Body that issued the instrument
        # @return [String, nil]
        attribute :issuing_body, :string

        # Date of issuance/publication
        # @return [Date, nil]
        attribute :issuance_date, :date

        # Date of entry into force
        # @return [Date, nil]
        attribute :effective_date, :date

        # Official URL to the instrument
        # @return [String, nil]
        attribute :url, :string

        # Programme/regime code this instrument belongs to
        # @return [String, nil]
        attribute :programme, :string

        # Check if instrument has meaningful content
        # @return [Boolean]
        def present?
          [identifier, title].any?(&:present?)
        end

        # Get type as normalized symbol
        # @return [Symbol]
        def type_sym
          Types.normalize_instrument_type(type)
        end

        # Get display string
        # @return [String]
        def to_s
          identifier || title || 'Unknown instrument'
        end

        # Convert to hash for JSON-LD serialization
        # @return [Hash]
        def to_hash
          hash = {}
          hash[:type] = type if type
          hash[:identifier] = identifier if identifier
          hash[:title] = title if title
          hash[:issuing_body] = issuing_body if issuing_body
          hash[:issuance_date] = issuance_date.to_s if issuance_date
          hash[:effective_date] = effective_date.to_s if effective_date
          hash[:url] = url if url
          hash[:programme] = programme if programme
          hash
        end

        # JSON mapping
        json do
          map :type, to: :type
          map :identifier, to: :identifier
          map :title, to: :title
          map :issuing_body, to: :issuing_body
          map :issuance_date, to: :issuance_date
          map :effective_date, to: :effective_date
          map :url, to: :url
          map :programme, to: :programme
        end

        # YAML mapping
        yaml do
          map :type, to: :type
          map :identifier, to: :identifier
          map :title, to: :title
          map :issuing_body, to: :issuing_body
          map :issuance_date, to: :issuance_date
          map :effective_date, to: :effective_date
          map :url, to: :url
          map :programme, to: :programme
        end
      end
    end
  end
end
