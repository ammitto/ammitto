# frozen_string_literal: true

require_relative '../utils/iri_sanitizer'

module Ammitto
  module Ontology
    # SanctionsList represents a specific sanctions list from a source.
    #
    # Each list is uniquely identified by source + list_type.
    # Lists contain metadata about the sanctions regime and can be
    # queried for their entries.
    #
    # @example Creating a list
    #   list = SanctionsList.new(
    #     source: 'cn',
    #     list_type: 'import-export-control-list',
    #     name: 'Import-Export Control List',
    #     name_chinese: '出口管制管控名单',
    #     authority: 'MOFCOM'
    #   )
    #
    # @example Getting the list IRI
    #   list.iri  # => "https://www.ammitto.org/list/cn/import-export-control-list"
    #
    class SanctionsList
      attr_reader :source, :list_type, :name, :name_chinese, :name_russian,
                  :authority, :description, :url, :established_date,
                  :legal_instrument_ids

      # Initialize a new SanctionsList.
      #
      # @param source [String] Source code (e.g., "cn", "ru")
      # @param list_type [String] List type identifier (e.g., "import-export-control-list")
      # @param name [String] English name of the list
      # @param name_chinese [String, nil] Chinese name (optional)
      # @param name_russian [String, nil] Russian name (optional)
      # @param authority [String] Issuing authority
      # @param description [String, nil] Description of the list
      # @param url [String, nil] Official URL for the list
      # @param established_date [String, nil] Date the list was established
      # @param legal_instrument_ids [Array<String>] IDs of legal instruments
      #
      def initialize(source:, list_type:, name:, authority:,
                     name_chinese: nil, name_russian: nil,
                     description: nil, url: nil, established_date: nil,
                     legal_instrument_ids: [])
        @source = source
        @list_type = list_type
        @name = name
        @name_chinese = name_chinese
        @name_russian = name_russian
        @authority = authority
        @description = description
        @url = url
        @established_date = established_date
        @legal_instrument_ids = legal_instrument_ids
      end

      # Get the unique IRI for this list.
      #
      # @return [String] The list IRI
      #
      def iri
        Utils::IriSanitizer.list_type_iri(source, list_type)
      end

      # Get the unique ID for this list (same as list_type within source context).
      #
      # @return [String] The list type identifier
      #
      def id
        list_type
      end

      # Convert to a hash for serialization.
      #
      # @return [Hash] Hash representation
      #
      def to_h
        {
          'id' => list_type,
          'iri' => iri,
          'source' => source,
          'name' => name,
          'name_chinese' => name_chinese,
          'name_russian' => name_russian,
          'authority' => authority,
          'description' => description,
          'url' => url,
          'established_date' => established_date,
          'legal_instrument_ids' => legal_instrument_ids
        }.compact
      end

      # Convert to YAML-friendly format for file storage.
      #
      # @return [Hash] YAML-friendly hash
      #
      def to_yaml_hash
        {
          'id' => list_type,
          'source' => source,
          'name' => name,
          'name_chinese' => name_chinese,
          'name_russian' => name_russian,
          'authority' => authority,
          'description' => description,
          'url' => url,
          'established_date' => established_date,
          'legal_instrument_ids' => legal_instrument_ids
        }.compact
      end

      # Create from a hash (e.g., from YAML file).
      #
      # @param hash [Hash] Hash with list data
      # @return [SanctionsList] New list instance
      #
      def self.from_hash(hash)
        new(
          source: hash['source'],
          list_type: hash['id'] || hash['list_type'],
          name: hash['name'],
          name_chinese: hash['name_chinese'],
          name_russian: hash['name_russian'],
          authority: hash['authority'],
          description: hash['description'],
          url: hash['url'],
          established_date: hash['established_date'],
          legal_instrument_ids: hash['legal_instrument_ids'] || []
        )
      end
    end
  end
end
