# frozen_string_literal: true

module Ammitto
  # BirthInfo represents birth-related information for a person
  #
  # Supports exact dates, approximate dates, year ranges, and location
  # information.
  #
  # == What each field is allowed to say
  #
  # +date+::  ONE complete source-stated day, month and year.
  # +year+::  ONE source-stated year.
  # +year_range_from+ / +year_range_to+:: the bounds of a source-stated
  #           span of years ("born between 1959 and 1965").
  #
  # A range never populates +year+ or +date+ with one of its endpoints:
  # neither bound is the birth year, and there is no honest third value,
  # so both stay nil while a range is present. Either bound may stand
  # alone, so "1953 or later" and "no later than 1958" are both
  # expressible. When both are present +year_range_from+ must not exceed
  # +year_range_to+; a reversed pair is rejected at the transformer
  # boundary rather than silently reordered, because reordering would
  # invent a claim the source never made.
  #
  # +circa+ is independent of a range. A range is a span the source
  # stated exactly, not an approximation, and sources emit circa
  # alongside a range in both settings — so circa is carried through from
  # the source and never inferred from the presence of a range.
  #
  # @example Creating birth info
  #   BirthInfo.new(
  #     date: "1964-07-17",
  #     city: "Pyongyang",
  #     country: "Democratic People's Republic of Korea"
  #   )
  #
  # @example A source-stated span of years
  #   BirthInfo.new(year_range_from: 1959, year_range_to: 1965, circa: true)
  #
  class BirthInfo < Lutaml::Model::Serializable
    attribute :date, :date
    attribute :circa, :boolean, default: false  # Approximate date
    attribute :year, :integer                   # Year only if full date unknown
    attribute :year_range_from, :integer        # Lower bound of a year span
    attribute :year_range_to, :integer          # Upper bound of a year span
    attribute :city, :string
    attribute :region, :string                  # State, province, etc.
    attribute :country, :string                 # Country name
    attribute :country_iso_code, :string        # ISO 3166-1 alpha-2

    json do
      map 'date', to: :date
      map 'circa', to: :circa
      map 'year', to: :year
      map 'yearRangeFrom', to: :year_range_from
      map 'yearRangeTo', to: :year_range_to
      map 'city', to: :city
      map 'region', to: :region
      map 'country', to: :country
      map 'countryIsoCode', to: :country_iso_code
    end

    # @return [String] formatted birth location
    def location
      [city, region, country].compact.reject(&:empty?).join(', ')
    end

    # @return [Boolean] whether a year span is stated, on either side
    def year_range?
      !year_range_from.nil? || !year_range_to.nil?
    end

    # A range renders as its span rather than as a single year, and an
    # open bound renders as the direction it leaves open: "1953 or
    # later", "no later than 1958".
    # @return [String, nil] formatted birth date, year, or year span
    def formatted_date
      return with_circa(formatted_year_range) if year_range?
      return with_circa(year.to_s) if year && !date
      return nil unless date

      with_circa(date.to_s)
    end

    private

    # @return [String] the span, closed or open on either side
    def formatted_year_range
      return "#{year_range_from}-#{year_range_to}" if year_range_from && year_range_to
      return "#{year_range_from} or later" if year_range_from

      "no later than #{year_range_to}"
    end

    # @param label [String] the rendered date, year or span
    # @return [String] the label, prefixed when the source said circa
    def with_circa(label)
      circa ? "c. #{label}" : label
    end
  end
end
