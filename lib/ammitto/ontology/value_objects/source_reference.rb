# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Ontology
    module ValueObjects
      # SourceReference represents a reference to an external source
      #
      # Used to track where entity information came from and maintain
      # provenance for data quality and verification.
      #
      # @example Creating a source reference
      #   SourceReference.new(
      #     source_code: "eu",
      #     reference_number: "EU.1234",
      #     resolution: "2023/1234",
      #     fetched_at: "2024-01-15T10:30:00Z"
      #   )
      #
      class SourceReference < Lutaml::Model::Serializable
        # Source identifier (eu, un, us, etc.)
        # @return [String, nil]
        attribute :source_code, :string

        # ID in the source system
        # @return [String, nil]
        attribute :reference_number, :string

        # UN resolution or other legal basis (for UN sources)
        # @return [String, nil]
        attribute :resolution, :string

        # URL to the source
        # @return [String, nil]
        attribute :url, :string

        # When the data was retrieved (ISO 8601)
        # @return [String, nil]
        attribute :fetched_at, :string

        # Convert to hash for JSON-LD serialization
        # @return [Hash]
        def to_hash
          hash = {}
          hash[:source_code] = source_code if source_code
          hash[:reference_number] = reference_number if reference_number
          hash[:resolution] = resolution if resolution
          hash[:url] = url if url
          hash[:fetched_at] = fetched_at if fetched_at
          hash
        end

        # JSON mapping
        json do
          map 'sourceCode', to: :source_code
          map 'referenceNumber', to: :reference_number
          map 'resolution', to: :resolution
          map 'url', to: :url
          map 'fetchedAt', to: :fetched_at
        end

        # YAML mapping
        yaml do
          map 'source_code', to: :source_code
          map 'reference_number', to: :reference_number
          map 'resolution', to: :resolution
          map 'url', to: :url
          map 'fetched_at', to: :fetched_at
        end
      end
    end
  end
end
