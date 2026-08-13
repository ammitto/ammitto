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
      # may be a span of dates or of years, and may be approximate
      # (circa flag).
      #
      # +date+ carries ONE complete source-stated day/month/year and
      # +year+ ONE source-stated year. A source-stated span rides in
      # +date_range_from+ / +date_range_to+ when the source stated
      # complete endpoint dates, and in +year_range_from+ /
      # +year_range_to+ when it stated years. While a span is present
      # +date+ stays nil: neither bound is the birth date. +year+ stays
      # nil too, unless a date span's endpoints share one year — then
      # the whole interval lies inside that year and the scalar is read
      # out rather than invented. A date span also publishes its
      # endpoint years through the year bounds, so year-only consumers
      # keep finding the record; those derived bounds supplement the
      # complete dates, they do not replace them. Either bound may stand
      # alone. A reversed closed pair is rejected upstream, at the
      # transformer boundary, rather than reordered here.
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
      # @example A source-stated span of complete dates
      #   BirthInfo.new(date_range_from: Date.new(1961, 1, 1),
      #                 date_range_to: Date.new(1962, 12, 31))
      #
      class BirthInfo < Lutaml::Model::Serializable
        include Neo4jAdapter

        # Neo4j configuration for BirthInfo
        neo4j_labels 'BirthInfo'
        neo4j_property :date, :circa, :year, :date_range_from,
                       :date_range_to, :year_range_from, :year_range_to,
                       :city, :region, :country, :country_iso_code

        # Exact or approximate birth date
        # @return [Date, nil]
        attribute :date, :date

        # Whether the date is approximate (circa)
        # @return [Boolean]
        attribute :circa, :boolean, default: false

        # Birth year only (when exact date unknown)
        # @return [Integer, nil]
        attribute :year, :integer

        # Lower bound of a source-stated span of complete birth dates
        # @return [Date, nil]
        attribute :date_range_from, :date

        # Upper bound of a source-stated span of complete birth dates
        # @return [Date, nil]
        attribute :date_range_to, :date

        # Lower bound of a birth-year span: either source-stated, or
        # derived from a date span's endpoints for year-only discovery
        # @return [Integer, nil]
        attribute :year_range_from, :integer

        # Upper bound of a birth-year span: either source-stated, or
        # derived from a date span's endpoints for year-only discovery
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
          [date, year, date_range_from, date_range_to, year_range_from,
           year_range_to, city, region, country].any? do |v|
            Utils::Presence.present?(v)
          end
        end

        # Whether a span of complete dates is stated, on either side
        # @return [Boolean]
        def date_range?
          !date_range_from.nil? || !date_range_to.nil?
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
          hash[:date_range_from] = date_range_from.to_s if date_range_from
          hash[:date_range_to] = date_range_to.to_s if date_range_to
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
          return date_range_label if date_range?
          return year_range_label if year_range?
          return year.to_s if year && !date
          return date.to_s if date

          nil
        end

        # The date range precedes the year range derived from it,
        # because it preserves everything the source stated.
        # @return [String] the span, closed or open on either side
        def date_range_label
          closed = date_range_from && date_range_to
          return "#{date_range_from}-#{date_range_to}" if closed
          return "#{date_range_from} or later" if date_range_from

          "no later than #{date_range_to}"
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
          map :date_range_from, to: :date_range_from
          map :date_range_to, to: :date_range_to
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
          map :date_range_from, to: :date_range_from
          map :date_range_to, to: :date_range_to
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
