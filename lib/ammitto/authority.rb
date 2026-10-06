# frozen_string_literal: true

require 'lutaml/model'
require_relative 'utils/iri_sanitizer'

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
      'tr' => { name: 'Turkey (Ministry of Treasury and Finance)', country_code: 'TR' },
      'nz' => { name: 'New Zealand (MFAT)', country_code: 'NZ' },
      'jp' => { name: 'Japan (METI End-User List)', country_code: 'JP' },
      'eu_vessels' => { name: 'EU Designated Vessels (via Denmark DMA)', country_code: 'EU' },
      'un_vessels' => { name: 'UN Security Council (1718 Committee)', country_code: 'UN' },
      'jp_meti' => { name: 'Japan METI (Ministry of Economy, Trade and Industry)', country_code: 'JP' }
    }.freeze

    # An authority code: an ASCII letter or digit, then letters, digits, `_`
    # and `-` (un, eu_vessels).
    CODE = /\A[A-Za-z0-9][A-Za-z0-9_-]*\z/
    AUTHORITY_IRI = %r{\A#{Regexp.escape(Utils::IriSanitizer::BASE_URI)}/authority/([^/]+)/?\z}

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

    # The authority code a value stands for, in the one spelling every
    # reader compares: lower case, no IRI.
    #
    # Data names an authority as an IRI on Ammitto's own base
    # (`https://www.ammitto.org/authority/<code>`, the form
    # Utils::IriSanitizer.authority_iri builds), a bare code, or a node
    # carrying either under '@id' or 'id' (string or symbol keys). Any other
    # IRI, including an `/authority/` path on a foreign host, names no
    # authority of ours, and neither does a value that is not a code (blank,
    # spaces, a path, a query) or a type this does not read.
    #
    # @param value [String, Hash, Object] an authority reference
    # @return [String, nil] the code, or nil when the value names none
    def self.code_from(value)
      case value
      when Hash
        value.values_at('@id', :@id, 'id', :id).filter_map { |v| code_from(v) }.first
      when String
        code_from_string(value)
      end
    end

    # The text is checked as given: a padded code would also pass for a
    # padded entity IRI segment, which names no authority.
    def self.code_from_string(text)
      code = text.match(AUTHORITY_IRI)&.[](1) || text
      code.match?(CODE) ? code.downcase : nil
    end
    private_class_method :code_from_string

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
