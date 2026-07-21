# frozen_string_literal: true

module Ammitto
  # BirthInfo represents birth-related information for a person
  #
  # Supports exact dates, approximate dates, and location information.
  #
  # @example Creating birth info
  #   BirthInfo.new(
  #     date: "1964-07-17",
  #     city: "Pyongyang",
  #     country: "Democratic People's Republic of Korea"
  #   )
  #
  class BirthInfo < Lutaml::Model::Serializable
    attribute :date, :date
    attribute :circa, :boolean, default: false  # Approximate date
    attribute :year, :integer                   # Year only if full date unknown
    attribute :city, :string
    attribute :region, :string                  # State, province, etc.
    attribute :country, :string                 # Country name
    attribute :country_iso_code, :string        # ISO 3166-1 alpha-2

    json do
      map 'date', to: :date
      map 'circa', to: :circa
      map 'year', to: :year
      map 'city', to: :city
      map 'region', to: :region
      map 'country', to: :country
      map 'countryIsoCode', to: :country_iso_code
    end

    # @return [String] formatted birth location
    def location
      [city, region, country].compact.reject(&:empty?).join(', ')
    end

    # @return [String, nil] formatted birth date or year
    def formatted_date
      return year.to_s if year && !date
      return nil unless date

      circa ? "c. #{date}" : date.to_s
    end
  end
end
