# frozen_string_literal: true

module Ammitto
  # RawSourceData preserves the original source data
  #
  # Stores the original XML/JSON/HTML and source-specific fields
  # for audit, verification, and future field extraction.
  #
  # @example Creating raw source data
  #   RawSourceData.new(
  #     source_file: "un-consolidated_2024-01-15.xml",
  #     source_format: "xml",
  #     raw_content: "<INDIVIDUAL>...</INDIVIDUAL>",
  #     source_specific_fields: { "un:dataId" => "6908555" }
  #   )
  #
  class RawSourceData < Lutaml::Model::Serializable
    # Source formats
    FORMATS = %w[xml json csv html].freeze

    attribute :source_file, :string           # Original file name
    attribute :source_format, :string         # xml, json, csv, html
    attribute :source_xpath, :string          # XPath for XML sources
    attribute :raw_content, :string           # Original content snippet
    attribute :source_specific_fields, :hash  # Source-specific fields

    json do
      map 'sourceFile', to: :source_file
      map 'sourceFormat', to: :source_format
      map 'sourceXPath', to: :source_xpath
      map 'rawContent', to: :raw_content
      map 'sourceSpecificFields', to: :source_specific_fields
    end

    # Get a source-specific field value
    # @param key [String] the field key
    # @return [Object, nil] the field value
    def field(key)
      source_specific_fields&.[](key)
    end

    # @return [Boolean] whether raw content is present
    def has_raw_content?
      !raw_content.nil? && !raw_content.empty?
    end
  end
end
