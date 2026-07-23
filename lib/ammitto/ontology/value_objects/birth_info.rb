# frozen_string_literal: true

require 'lutaml/model'
require_relative '../../utils/presence'
require_relative '../neo4j_adapter'

module Ammitto
  module Ontology
    module ValueObjects
      # Represents birth information for a person
      #
      # Birth information may be partial (year only, city only, etc.)
      # and may be approximate (circa flag).
      #
      # @example Creating birth info
      #   birth = BirthInfo.new(
      #     date: Date.new(1970, 5, 15),
      #     circa: false,
      #     city: "Moscow",
      #     region: "Moscow Oblast",
      #     country: "Russia",
      #     country_iso_code: "RU"
      #   )
      #
      class BirthInfo < Lutaml::Model::Serializable
        include Neo4jAdapter

        # Neo4j configuration for BirthInfo
        neo4j_labels 'BirthInfo'
        neo4j_property :date, :circa, :year, :city, :region, :country, :country_iso_code

        # Exact or approximate birth date
        # @return [Date, nil]
        attribute :date, :date

        # Whether the date is approximate (circa)
        # @return [Boolean]
        attribute :circa, :boolean, default: false

        # Birth year only (when exact date unknown)
        # @return [Integer, nil]
        attribute :year, :integer

        # City / town of birth
        # @return [String, nil]
        attribute :city, :string

        # Region / state / province of birth
        # @return [String, nil]
        attribute :region, :string

        # Country of birth (free text)
        # @return [String, nil]
        attribute :country, :string

        # ISO 3166-1 alpha-2 country code
        # @return [String, nil]
        attribute :country_iso_code, :string

        # Check if birth info has meaningful content
        # @return [Boolean]
        def present?
          [date, year, city, country].any? { |v| Utils::Presence.present?(v) }
        end

        # Get year of birth (from date or year field)
        # @return [Integer, nil]
        def birth_year
          date&.year || year
        end

        # Get display string
        # @return [String]
        def to_s
          parts = []
          parts << 'c.' if circa
          parts << date_label if date_label
          parts << [city, region, country].compact.join(', ') if city || country
          parts.join(' ')
        end

        def to_hash
          hash = {}
          hash[:date] = date.to_s if date
          hash[:circa] = circa if circa
          hash[:year] = year if year
          hash[:city] = city if city
          hash[:region] = region if region
          hash[:country] = country if country
          hash[:country_iso_code] = country_iso_code if country_iso_code
          hash
        end

        private

        def date_label
          return year.to_s if year && !date
          return date.to_s if date

          nil
        end

        # Convert to hash for JSON-LD serialization
        # @return [Hash]

        # JSON mapping
        json do
          map :date, to: :date
          map :circa, to: :circa
          map :year, to: :year
          map :city, to: :city
          map :region, to: :region
          map :country, to: :country
          map :country_iso_code, to: :country_iso_code
        end

        # YAML mapping
        yaml do
          map :date, to: :date
          map :circa, to: :circa
          map :year, to: :year
          map :city, to: :city
          map :region, to: :region
          map :country, to: :country
          map :country_iso_code, to: :country_iso_code
        end
      end
    end
  end
end
