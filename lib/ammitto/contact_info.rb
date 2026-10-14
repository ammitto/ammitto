# frozen_string_literal: true

require_relative 'ontology/contracts'
require_relative 'ontology/value_objects/contact_info'

module Ammitto
  # ContactInfo represents contact information
  #
  # Legacy facade: its fields are projected from
  # Ontology::ValueObjects::ContactInfo (see Ontology::Contracts).
  #
  # @example Creating contact info
  #   ContactInfo.new(
  #     phone: "+1-555-123-4567",
  #     email: "info@example.com",
  #     website: "https://example.com"
  #   )
  #
  class ContactInfo < Lutaml::Model::Serializable
    Ontology::Contracts.declare_legacy_attributes(self)

    json do
      map 'phone', to: :phone
      map 'fax', to: :fax
      map 'email', to: :email
      map 'website', to: :website
      map 'note', to: :note
    end

    # @return [Boolean] whether any contact info is present
    def present?
      [phone, fax, email, website].any? { |v| v && !v.empty? }
    end
  end
end
