# frozen_string_literal: true

module Ammitto
  # Address represents a physical address
  #
  # @example Creating an address
  #   Address.new(
  #     street: "123 Main St",
  #     city: "New York",
  #     state: "NY",
  #     country: "United States",
  #     postal_code: "10001"
  #   )
  #
  class Address < Lutaml::Model::Serializable
    attribute :street, :string
    attribute :street2, :string
    attribute :city, :string
    attribute :state, :string             # State, province, region
    attribute :country, :string           # Country name
    attribute :country_iso_code, :string  # ISO 3166-1 alpha-2
    attribute :postal_code, :string
    attribute :po_box, :string

    json do
      map 'street', to: :street
      map 'street2', to: :street2
      map 'city', to: :city
      map 'state', to: :state
      map 'country', to: :country
      map 'country_iso_code', to: :country_iso_code
      map 'countryIsoCode', to: :country_iso_code  # backward compatibility
      map 'postal_code', to: :postal_code
      map 'postalCode', to: :postal_code  # backward compatibility
      map 'po_box', to: :po_box
      map 'poBox', to: :po_box  # backward compatibility
    end

    # @return [String] formatted single-line address
    def to_s
      parts = [street, street2, city, state, postal_code, country].compact
      parts.reject(&:empty?).join(', ')
    end

    # @return [Boolean] whether the address has any data
    def present?
      [street, city, state, country, postal_code].any? { |v| v && !v.empty? }
    end
  end
end
