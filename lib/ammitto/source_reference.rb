# frozen_string_literal: true

module Ammitto
  # SourceReference represents a reference to an external source
  #
  # Used to track where entity information came from.
  #
  # @example Creating a source reference
  #   SourceReference.new(
  #     source_code: :eu,
  #     reference_number: "EU.1234",
  #     url: "https://..."
  #   )
  #
  class SourceReference < Lutaml::Model::Serializable
    attribute :source_code, :string      # Source identifier (eu, un, us, etc.)
    attribute :reference_number, :string # ID in the source system
    attribute :url, :string              # URL to the source
    attribute :retrieved_at, :string # When the data was retrieved (ISO 8601)

    json do
      map 'sourceCode', to: :source_code
      map 'referenceNumber', to: :reference_number
      map 'url', to: :url
      map 'retrievedAt', to: :retrieved_at
    end
  end
end
