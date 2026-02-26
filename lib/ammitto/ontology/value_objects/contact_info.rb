# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Ontology
    module ValueObjects
      # Represents contact information for an entity
      #
      # Contact information may include email, phone, website, etc.
      #
      # @example Creating contact info
      #   contact = ContactInfo.new(
      #     email: "contact@example.com",
      #     phone: "+1-555-123-4567",
      #     website: "https://example.com",
      #     fax: "+1-555-123-4568"
      #   )
      #
      class ContactInfo < Lutaml::Model::Serializable
        # Email address
        # @return [String, nil]
        attribute :email, :string

        # Phone number
        # @return [String, nil]
        attribute :phone, :string

        # Website URL
        # @return [String, nil]
        attribute :website, :string

        # Fax number
        # @return [String, nil]
        attribute :fax, :string

        # Check if contact info has meaningful content
        # @return [Boolean]
        def present?
          [email, phone, website, fax].any?(&:present?)
        end

        # Check if contact info is empty
        # @return [Boolean]
        def blank?
          !present?
        end

        # Convert to hash for JSON-LD serialization
        # @return [Hash]
        def to_hash
          hash = {}
          hash[:email] = email if email
          hash[:phone] = phone if phone
          hash[:website] = website if website
          hash[:fax] = fax if fax
          hash
        end

        # JSON mapping
        json do
          map :email, to: :email
          map :phone, to: :phone
          map :website, to: :website
          map :fax, to: :fax
        end

        # YAML mapping
        yaml do
          map :email, to: :email
          map :phone, to: :phone
          map :website, to: :website
          map :fax, to: :fax
        end
      end
    end
  end
end
