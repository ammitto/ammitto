# frozen_string_literal: true

require 'lutaml/model'
require_relative '../types'

module Ammitto
  module Ontology
    module ValueObjects
      # Represents an identification document
      #
      # Identification documents can be passports, national IDs,
      # tax IDs, etc. Each document has a type, number, and
      # optionally an issuing country.
      #
      # @example Creating an identification
      #   id = Identification.new(
      #     type: :passport,
      #     number: "A12345678",
      #     issuing_country: "RU",
      #     expiry_date: Date.new(2025, 12, 31)
      #   )
      #
      class Identification < Lutaml::Model::Serializable
        # Type of identification document
        # @return [Symbol, String, nil]
        attribute :type, :string

        # Document number
        # @return [String, nil]
        attribute :number, :string

        # Country that issued the document (ISO 3166-1 alpha-2)
        # @return [String, nil]
        attribute :issuing_country, :string

        # Document expiry date
        # @return [Date, nil]
        attribute :expiry_date, :date

        # Issue date
        # @return [Date, nil]
        attribute :issue_date, :date

        # Check if identification has meaningful content
        # @return [Boolean]
        def present?
          number.present?
        end

        # Get type as normalized symbol
        # @return [Symbol]
        def type_sym
          Types.normalize_identification_type(type)
        end

        # Convert to hash for JSON-LD serialization
        # @return [Hash]
        def to_hash
          hash = {}
          hash[:type] = type if type
          hash[:number] = number if number
          hash[:issuing_country] = issuing_country if issuing_country
          hash[:expiry_date] = expiry_date.to_s if expiry_date
          hash[:issue_date] = issue_date.to_s if issue_date
          hash
        end

        # JSON mapping
        json do
          map :type, to: :type
          map :number, to: :number
          map :issuing_country, to: :issuing_country
          map :expiry_date, to: :expiry_date
          map :issue_date, to: :issue_date
        end

        # YAML mapping
        yaml do
          map :type, to: :type
          map :number, to: :number
          map :issuing_country, to: :issuing_country
          map :expiry_date, to: :expiry_date
          map :issue_date, to: :issue_date
        end
      end
    end
  end
end
