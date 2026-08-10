# frozen_string_literal: true

require 'lutaml/model'
require_relative '../../utils/presence'
require_relative '../neo4j_adapter'

module Ammitto
  module Ontology
    module ValueObjects
      # Represents birth information for a person
      #
      # Birth information may be partial (year only, city only, etc.),
      # may be a span of years, and may be approximate (circa flag).
      #
      # +date+ carries ONE complete source-stated day/month/year and
      # +year+ ONE source-stated year. A source-stated span rides in
      # +year_range_from+ / +year_range_to+ instead, and while a span is
      # present +date+ and +year+ stay nil: neither bound is the birth
      # year, so filling +year+ with an endpoint would assert something
      # the source never said. Either bound may stand alone. A reversed
      # closed pair is rejected upstream, at the transformer boundary,
      # rather than reordered here.
      #
      # +circa+ is independent of a span: sources emit circa both with
      # and without a range, so it is carried from the source and never
      # inferred.
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
      # @example A source-stated span of years
      #   BirthInfo.new(year_range_from: 1959, year_range_to: 1965)
      #
      class BirthInfo < Lutaml::Model::Serializable
        include Neo4jAdapter

        # Neo4j configuration for BirthInfo
        neo4j_labels 'BirthInfo'
        neo4j_property :date, :circa, :year, :year_range_from,
                       :year_range_to, :city, :region, :country,
                       :country_iso_code

        # Exact or approximate birth date
        # @return [Date, nil]
        attribute :date, :date

        # Whether the date is approximate (circa)
        # @return [Boolean]
        attribute :circa, :boolean, default: false

        # Birth year only (when exact date unknown)
        # @return [Integer, nil]
        attribute :year, :integer

        # Lower bound of a source-stated span of birth years
        # @return [Integer, nil]
        attribute :year_range_from, :integer

        # Upper bound of a source-stated span of birth years
        # @return [Integer, nil]
        attribute :year_range_to, :integer

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
          [date, year, year_range_from, year_range_to, city, region,
           country].any? do |v|
            Utils::Presence.present?(v)
          end
        end

        # Whether a span of years is stated, on either side
        # @return [Boolean]
        def year_range?
          !year_range_from.nil? || !year_range_to.nil?
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
          label = date_label
          parts << 'c.' if circa && label
          parts << label if label
          place = [city, region, country].compact
          parts << place.join(', ') unless place.empty?
          parts.join(' ')
        end

        # Convert to hash for JSON-LD serialization
        # @return [Hash]
        def to_hash
          hash = {}
          hash[:date] = date.to_s if date
          hash[:circa] = circa if circa
          hash[:year] = year if year
          hash[:year_range_from] = year_range_from if year_range_from
          hash[:year_range_to] = year_range_to if year_range_to
          hash[:city] = city if city
          hash[:region] = region if region
          hash[:country] = country if country
          hash[:country_iso_code] = country_iso_code if country_iso_code
          hash
        end

        private

        def date_label
          return year_range_label if year_range?
          return year.to_s if year && !date
          return date.to_s if date

          nil
        end

        # An open bound renders as the direction it leaves open, so a
        # one-sided span is never mistaken for a closed one.
        # @return [String] the span, closed or open on either side
        def year_range_label
          closed = year_range_from && year_range_to
          return "#{year_range_from}-#{year_range_to}" if closed
          return "#{year_range_from} or later" if year_range_from

          "no later than #{year_range_to}"
        end

        # JSON mapping
        json do
          map :date, to: :date
          map :circa, to: :circa
          map :year, to: :year
          map :year_range_from, to: :year_range_from
          map :year_range_to, to: :year_range_to
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
          map :year_range_from, to: :year_range_from
          map :year_range_to, to: :year_range_to
          map :city, to: :city
          map :region, to: :region
          map :country, to: :country
          map :country_iso_code, to: :country_iso_code
        end
      end
    end
  end
end
