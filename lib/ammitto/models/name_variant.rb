# frozen_string_literal: true

module Ammitto
  # NameVariant represents a name with various components and metadata
  #
  # Supports full names, split names, multiple scripts and languages,
  # and additional attributes like title and function.
  #
  # @example Creating a name variant
  #   NameVariant.new(
  #     full_name: "John Smith",
  #     first_name: "John",
  #     last_name: "Smith",
  #     script: "Latn",
  #     is_primary: true
  #   )
  #
  class NameVariant < Lutaml::Model::Serializable
    attribute :full_name, :string
    attribute :first_name, :string
    attribute :middle_name, :string
    attribute :last_name, :string
    attribute :script, :string         # Latn, Cyrl, Arab, Hani, etc.
    attribute :language, :string       # ISO 639-1 code
    attribute :is_primary, :boolean, default: false
    attribute :title, :string          # Mr., Dr., Prof., etc.
    attribute :function, :string       # Role or position

    # JSON mapping
    json do
      map 'fullName', to: :full_name
      map 'firstName', to: :first_name
      map 'middleName', to: :middle_name
      map 'lastName', to: :last_name
      map 'script', to: :script
      map 'language', to: :language
      map 'isPrimary', to: :is_primary
      map 'title', to: :title
      map 'function', to: :function
    end

    # @return [String] the display name
    def display_name
      full_name || [first_name, middle_name, last_name].compact.join(' ')
    end

    # @return [Boolean] whether this is a primary name
    def primary?
      is_primary == true
    end
  end
end
