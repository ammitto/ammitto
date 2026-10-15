# frozen_string_literal: true

require 'lutaml/model'
require_relative 'immutable'

module Ammitto
  module Ontology
    module ValueObjects
      # The original source record behind a harmonized value, kept verbatim
      # for audit and later re-extraction
      #
      # @example
      #   RawSourceData.new(
      #     source_file: "un-consolidated_2024-01-15.xml",
      #     source_format: "xml",
      #     raw_content: "<INDIVIDUAL>...</INDIVIDUAL>",
      #     source_specific_fields: { "un:dataId" => "6908555" }
      #   )
      #
      class RawSourceDataModel < Lutaml::Model::Serializable
        # Original file name
        # @return [String, nil]
        attribute :source_file, :string

        # Source format (xml, json, csv, html)
        # @return [String, nil]
        attribute :source_format, :string

        # XPath of the record inside an XML source
        # @return [String, nil]
        attribute :source_xpath, :string

        # The original record, unparsed
        # @return [String, nil]
        attribute :raw_content, :string

        # Source-specific fields with no harmonized home
        # @return [Hash, nil]
        attribute :source_specific_fields, :hash

        key_value do
          map :source_file, to: :source_file
          map :source_format, to: :source_format
          map :source_xpath, to: :source_xpath
          map :raw_content, to: :raw_content
          map :source_specific_fields, to: :source_specific_fields
        end
      end
      private_constant :RawSourceDataModel
    end
  end
end
