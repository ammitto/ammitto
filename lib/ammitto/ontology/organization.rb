# frozen_string_literal: true

require 'lutaml/model'
require_relative 'value_objects/localized_string'

module Ammitto
  module Ontology
    # Represents an organization in the sanctions ecosystem
    #
    # Organizations include government bodies, ministries, agencies, and
    # intergovernmental organizations that issue or enforce sanctions
    #
    # @example Creating an organization
    #   org = Organization.new(
    #     id: "cn/ministry-of-commerce",
    #     name: [
    #       LocalizedString.new(value: "中华人民共和国商务部", language: "zh", script: "Hani"),
    #       LocalizedString.new(value: "Ministry of Commerce, People's Republic of China", language: "en", script: "Latn")
    #     ],
    #     type: "ministry"
    #   )
    #
    class Organization < Lutaml::Model::Serializable
      # Unique identifier for the organization
      # @return [String]
      attribute :id, :string

      # Localized name of the organization
      # @return [Array<LocalizedString>]
      attribute :name, ValueObjects::LocalizedString, collection: true

      # Type of organization (ministry, department, agency, etc.)
      # @return [String, nil]
      attribute :type, :string

      # Parent organization ID
      # @return [String, nil]
      attribute :parent_id, :string

      # Official website URL
      # @return [String, nil]
      attribute :url, :string

      # Convert to hash for JSON-LD serialization
      # @return [Hash]
      def to_hash
        {
          '@context' => 'https://www.ammitto.org/ontology/context.jsonld',
          '@id' => id.start_with?('http') ? id : "https://www.ammitto.org/organization/#{id}",
          '@type' => 'Organization',
          'name' => name.map(&:to_hash)
        }.tap do |hash|
          hash['type'] = type if type
          hash['parentId'] = parent_id if parent_id
          hash['url'] = url if url
        end
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
        map 'type', to: :type
        map 'parent_id', to: :parent_id
        map 'url', to: :url
      end

      yaml do
        map 'id', to: :id
        map 'name', to: :name
        map 'type', to: :type
        map 'parent_id', to: :parent_id
        map 'url', to: :url
      end
    end
  end
end
