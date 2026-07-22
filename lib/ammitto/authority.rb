# frozen_string_literal: true

module Ammitto
  # Authority represents a sanctions-issuing authority
  #
  # @example Creating an authority
  #   Authority.new(
  #     id: "eu",
  #     name: "European Union",
  #     country_code: "EU"
  #   )
  #
  class Authority < Lutaml::Model::Serializable
    # Registry of known authorities
    REGISTRY = {
      'eu' => { name: 'European Union', country_code: 'EU' },
      'un' => { name: 'United Nations', country_code: 'UN' },
      'us' => { name: 'United States (OFAC)', country_code: 'US' },
      'wb' => { name: 'World Bank', country_code: 'WB' },
      'uk' => { name: 'United Kingdom (OFSI)', country_code: 'GB' },
      'au' => { name: 'Australia (DFAT)', country_code: 'AU' },
      'ca' => { name: 'Canada (SEFO)', country_code: 'CA' },
      'ch' => { name: 'Switzerland (SECO)', country_code: 'CH' },
      'cn' => { name: 'China (MOFCOM/MFA)', country_code: 'CN' },
      'ru' => { name: 'Russia (MID/CBR)', country_code: 'RU' },
      'tr' => { name: 'Turkey (Ministry of Interior)', country_code: 'TR' },
      'nz' => { name: 'New Zealand (MFAT)', country_code: 'NZ' },
      'jp' => { name: 'Japan (MOFA)', country_code: 'JP' },
      'eu_vessels' => { name: 'European Union (Vessels)', country_code: 'EU' },
      'un_vessels' => { name: 'United Nations (Vessels)', country_code: 'UN' }
    }.freeze

    attribute :id, :string                   # Authority identifier
    attribute :name, :string                 # Full name
    attribute :country_code, :string         # ISO 3166-1 alpha-2 (or custom)
    attribute :url, :string                  # Authority website

    json do
      map 'id', to: :id
      map 'name', to: :name
      map 'countryCode', to: :country_code
      map 'url', to: :url
    end

    # Get an authority by ID from the registry
    # @param id [String] the authority ID
    # @return [Authority, nil] the authority or nil if not found
    def self.find(id)
      data = REGISTRY[id.to_s.downcase]
      return nil unless data

      new(id: id.to_s.downcase, **data)
    end

    # Get all registered authorities
    # @return [Array<Authority>] list of all authorities
    def self.all
      REGISTRY.map { |id, data| new(id: id, **data) }
    end

    # @return [String] display name
    def to_s
      name
    end
  end
end
