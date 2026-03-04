# frozen_string_literal: true

require 'lutaml/model'
require 'ammitto/data/japan'

module Ammitto
  module Data
    module Japan
      module Meti
        # Entity represents a single entry in the Meti Foreign User List
        #
        # Each entity is an organization that may be involved in WMD proliferation.
        # The list is primarily for export control purposes.
        #
        # @example Creating an entity from parsed data
        #   entity = Ammitto::Data::Japan::Meti::Entity.new(
        #     id: 'jp.meti.ful.1',
        #     name_en: 'Al Qa\'ida/Islamic Army',
        #     country_code: 'AF',
        #     wmd_types: ['B', 'C', 'M', 'N', 'CW']
        #   )
        #
        class Entity < Lutaml::Model::Serializable
          # Unique identifier (format: jp.meti.ful.{number})
          attribute :id, :string

          # English name of the entity
          attribute :name_en, :string

          # Japanese name of the entity (if available)
          attribute :name_ja, :string

          # ISO 3166-1 alpha-2 country code
          attribute :country_code, :string

          # Japanese country name
          attribute :country_ja, :string

          # English country name
          attribute :country_en, :string

          # WMD type codes (N, M, B, C, CW)
          attribute :wmd_types, :string, collection: true

          # Alternative names (aliases)
          attribute :aliases, :string, collection: true

          # Entity type (always 'organization' for METI list)
          attribute :entity_type, :string, default: -> { 'organization' }

          # Source file name
          attribute :source_file, :string

          # Source URL
          attribute :source_url, :string

          # List date (from Excel file)
          attribute :list_date, :string

          # Original row number in the Excel file
          attribute :row_number, :integer

          xml do
            root 'Entity'
            map_element 'ID', to: :id
            map_element 'NameEN', to: :name_en
            map_element 'NameJA', to: :name_ja
            map_element 'CountryCode', to: :country_code
            map_element 'CountryJA', to: :country_ja
            map_element 'CountryEN', to: :country_en
            map_element 'WMDType', to: :wmd_types
            map_element 'Alias', to: :aliases
            map_element 'EntityType', to: :entity_type
            map_element 'SourceFile', to: :source_file
            map_element 'SourceURL', to: :source_url
            map_element 'ListDate', to: :list_date
            map_element 'RowNumber', to: :row_number
          end

          # Get the primary name (English preferred)
          # @return [String]
          def primary_name
            name_en || name_ja
          end

          # Get the reference number (extracted from ID)
          # @return [String]
          def reference_number
            id&.split('.')&.last
          end

          # Get WMD type descriptions
          # @return [Array<Hash>] array of { code:, ja:, en: }
          def wmd_descriptions
            wmd_types.map do |code|
              {
                code: code,
                ja: Ammitto::Data::Japan::WMD_TYPES[code]&.dig(:ja),
                en: Ammitto::Data::Japan::WMD_TYPES[code]&.dig(:en)
              }
            end
          end

          # Get the country name hash
          # @return [Hash] { ja:, en: }
          def country_name
            {
              ja: country_ja,
              en: country_en
            }.compact
          end

          # Convert to hash for YAML serialization
          # @return [Hash]
          def to_hash
            {
              'id' => id,
              'name' => {
                'en' => name_en,
                'ja' => name_ja
              }.compact,
              'type' => entity_type,
              'country_code' => country_code,
              'country_name' => country_name,
              'wmd_types' => wmd_types,
              'aliases' => aliases.nil? || aliases.empty? ? nil : aliases,
              'source_file' => source_file,
              'source_url' => source_url,
              'list_date' => list_date
            }.compact
          end
        end
      end
    end
  end
end
