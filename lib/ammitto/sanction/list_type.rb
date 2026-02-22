# frozen_string_literal: true

module Ammitto
  # ListType represents a type of sanctions list
  #
  # Different authorities have different list types, such as SDN List,
  # Unreliable Entity List, etc.
  #
  # @example Creating a list type
  #   ListType.new(
  #     name: "SDN List",
  #     category: "blocking"
  #   )
  #
  class ListType < Lutaml::Model::Serializable
    # List categories
    CATEGORIES = %w[
      blocking # Full asset freeze
      sectoral # Partial restrictions
      debarment # Procurement ban
      travel_ban # Entry restrictions
      unreliable_entity # China's unreliable entity list
      export_control # Export restrictions
      financial # Financial restrictions
    ].freeze

    attribute :name, :string # List name
    attribute :localized_name, :string, collection: true # Non-English names
    attribute :category, :string          # List category
    attribute :description, :string       # Description

    json do
      map 'name', to: :name
      map 'localizedName', to: :localized_name
      map 'category', to: :category
      map 'description', to: :description
    end

    # @return [String] display string
    def to_s
      name
    end
  end
end
