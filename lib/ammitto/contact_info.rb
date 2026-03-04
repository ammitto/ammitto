# frozen_string_literal: true

module Ammitto
  # ContactInfo represents contact information
  #
  # @example Creating contact info
  #   ContactInfo.new(
  #     phone: "+1-555-123-4567",
  #     email: "info@example.com",
  #     website: "https://example.com"
  #   )
  #
  class ContactInfo < Lutaml::Model::Serializable
    attribute :phone, :string
    attribute :fax, :string
    attribute :email, :string
    attribute :website, :string
    attribute :note, :string

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
