# frozen_string_literal: true

require_relative 'ontology/contracts'
require_relative 'ontology/value_objects/address'

module Ammitto
  # Address represents a physical address
  #
  # Legacy facade: its fields are projected from
  # Ontology::ValueObjects::Address (see Ontology::Contracts).
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
    Ontology::Contracts.declare_legacy_attributes(self)

    json do
      map 'street', to: :street
      map 'street2', to: :street2
      map 'city', to: :city
      map 'state', to: :state
      map 'country', to: :country
      map 'country_iso_code', to: :country_iso_code
      map 'countryIsoCode', to: :country_iso_code # backward compatibility
      map 'postal_code', to: :postal_code
      map 'postalCode', to: :postal_code # backward compatibility
      map 'po_box', to: :po_box
      map 'poBox', to: :po_box # backward compatibility
      map 'region', to: :region
      map 'address_type', to: :address_type
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
