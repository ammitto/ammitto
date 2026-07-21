# frozen_string_literal: true

require 'lutaml/model'
require_relative 'value_objects/localized_string'

module Ammitto
  module Ontology
    # Represents a document type in the sanctions ecosystem
    #
    # Document types categorize the various kinds of official documents
    # that announce or modify sanctions (e.g., orders, announcements, provisions)
    #
    # @example Creating a document type
    #   doc_type = DocumentType.new(
    #     id: "cn/ministry-of-commerce-order",
    #     name: [
    #       LocalizedString.new(value: "中华人民共和国商务部令", language: "zh", script: "Hani"),
    #       LocalizedString.new(value: "Order of the Ministry of Commerce", language: "en", script: "Latn")
    #     ]
    #   )
    #
    class DocumentType < Lutaml::Model::Serializable
      # Unique identifier for the document type
      # @return [String]
      attribute :id, :string

      # Localized name of the document type
      # @return [Array<LocalizedString>]
      attribute :name, ValueObjects::LocalizedString, collection: true

      # Convert to hash for JSON-LD serialization
      # @return [Hash]
      def to_hash
        {
          '@context' => 'https://www.ammitto.org/ontology/context.jsonld',
          '@id' => id.start_with?('http') ? id : "https://www.ammitto.org/document-type/#{id}",
          '@type' => 'DocumentType',
          'name' => name.map(&:to_hash)
        }
      end

      # Get primary (Chinese) name
      # @return [String, nil]
      def primary_name
        zh_name = name.find { |n| n.language == 'zh' }
        zh_name&.value
      end

      # Get English name
      # @return [String, nil]
      def english_name
        en_name = name.find { |n| n.language == 'en' }
        en_name&.value
      end

      # Get display name (prefers English, falls back to Chinese)
      # @return [String, nil]
      def display_name
        english_name || primary_name
      end

      json do
        map 'id', to: :id
        map 'name', to: :name
      end

      yaml do
        map 'id', to: :id
        map 'name', to: :name
      end
    end
  end
end
