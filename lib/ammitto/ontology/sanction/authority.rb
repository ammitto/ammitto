# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Ontology
    module Sanction
      # Represents a sanctions authority
      #
      # Authorities are governmental or intergovernmental bodies that
      # impose sanctions (EU, UN, US OFAC, etc.)
      #
      # @example Creating an authority
      #   authority = Authority.new(
      #     id: "eu",
      #     name: "European Union",
      #     country_code: "EU",
      #     url: "https://finance.ec.europa.eu/sanctions-dossier_en"
      #   )
      #
      class Authority < Lutaml::Model::Serializable
        # Unique identifier for the authority
        # @return [String]
        attribute :id, :string

        # Full name of the authority
        # @return [String]
        attribute :name, :string

        # ISO 3166-1 alpha-2 country code (or "EU", "UN" for international)
        # @return [String, nil]
        attribute :country_code, :string

        # Official website URL
        # @return [String, nil]
        attribute :url, :string

        # Convert to hash for JSON-LD serialization
        # @return [Hash]
        def to_hash
          hash = { id: id, name: name }
          hash[:country_code] = country_code if country_code
          hash[:url] = url if url
          hash
        end

        # JSON mapping
        json do
          map :id, to: :id
          map :name, to: :name
          map :country_code, to: :country_code
          map :url, to: :url
        end

        # YAML mapping
        yaml do
          map :id, to: :id
          map :name, to: :name
          map :country_code, to: :country_code
          map :url, to: :url
        end
      end
    end
  end
end
