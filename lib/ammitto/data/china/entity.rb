# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Data
    module China
      # Represents a sanctioned entity from Chinese government lists
      #
      # Can be either a person or organization with multilingual names,
      # sanctions measures, and related metadata.
      #
      # @example Person entity
      #   entity = Entity.new(
      #     type: 'person',
      #     names: [{ 'zh-Hans' => '余茂春', 'en' => 'Miles Yu' }],
      #     gender: 'male',
      #     title: '哈德逊研究所所长'
      #   )
      #
      # @example Organization entity
      #   entity = Entity.new(
      #     type: 'organization',
      #     names: [{ 'zh-Hans' => '洛克希德·马丁公司', 'en' => 'Lockheed Martin' }]
      #   )
      #
      class Entity < Lutaml::Model::Serializable
        # Name with language/script variant
        class Name < Lutaml::Model::Serializable
          attribute :value, :string
          attribute :lang, :string # 'zh-Hans', 'en', 'zh-Hant', etc.
          attribute :script, :string # ISO 15924 script code: 'Hani', 'Latn'
          attribute :is_primary, :boolean, default: false
          attribute :is_transliteration, :boolean, default: false

          yaml do
            map to: :value, with: { from: :from_value, to: :to_value }
            map 'lang', to: :lang
            map 'script', to: :script
            map 'is_primary', to: :is_primary
            map 'is_transliteration', to: :is_transliteration
          end

          def from_value(hash, value)
            # Handle hash format: { 'zh-Hans' => '值' } or { 'en' => 'value' }
            if value.is_a?(Hash)
              # First key-value pair
              lang, val = value.first
              hash['lang'] = lang
              hash['value'] = val
            else
              hash['value'] = value
            end
          end

          def to_value(_hash, doc)
            if lang
              doc[lang] = value
            else
              doc['value'] = value
            end
          end
        end

        # Sanction measure
        class Measure < Lutaml::Model::Serializable
          attribute :type, :string, collection: true
          attribute :description_zh, :string
          attribute :description_en, :string
          attribute :scope, :string

          yaml do
            map 'type', to: :type
            map 'zh-Hans', to: :description_zh
            map 'en', to: :description_en
            map 'scope', to: :scope
          end
        end

        # Reason for sanctioning
        class Reason < Lutaml::Model::Serializable
          attribute :text_zh, :string
          attribute :text_en, :string

          yaml do
            map 'zh-Hans', to: :text_zh
            map 'en', to: :text_en
          end
        end

        # Legal citation reference
        class Citation < Lutaml::Model::Serializable
          attribute :id, :string
          attribute :articles, :string, collection: true

          yaml do
            map 'id', to: :id
            map 'articles', to: :articles
          end
        end

        # Entity types
        TYPES = %w[person organization vessel aircraft].freeze

        attribute :id, :string
        attribute :type, :string
        attribute :names, Name, collection: true
        attribute :aliases, :string, collection: true

        # Person-specific
        attribute :gender, :string
        attribute :title_zh, :string
        attribute :title_en, :string
        attribute :birth_year, :string
        attribute :birth_date, :string
        attribute :birth_place, :string
        attribute :nationality, :string

        # Organization-specific
        attribute :country_of_registration, :string
        attribute :registration_number, :string

        # Sanctions
        attribute :measures, Measure, collection: true
        attribute :reasons, Reason, collection: true
        attribute :legal_citations, Citation, collection: true

        # Temporal
        attribute :effective_date, :date
        attribute :effective_time, :string
        attribute :listing_date, :date

        # List membership
        attribute :list_type, :string
        attribute :sanction_list, :string

        # Other
        attribute :remarks, :string
        attribute :status, :string, default: 'active'

        yaml do
          root 'entity'
          map 'id', to: :id
          map 'type', to: :type
          map 'names', to: :names
          map 'aliases', to: :aliases
          map 'gender', to: :gender
          map 'title', with: { from: :from_title, to: :to_title }
          map 'birth_info', with: { from: :from_birth_info, to: :to_birth_info }
          map 'country_of_registration', to: :country_of_registration
          map 'measures', to: :measures
          map 'reason', to: :reasons
          map 'effective_date', to: :effective_date
          map 'effective_time', to: :effective_time
          map 'sanction_list', to: :sanction_list
          map 'remarks', to: :remarks
        end

        def from_title(hash, value)
          case value
          when Hash
            hash['title_zh'] = value['zh-Hans']
            hash['title_en'] = value['en']
          else
            hash['title_zh'] = value
          end
        end

        def to_title(_hash, doc)
          return unless title_zh || title_en

          doc['title'] = {
            'zh-Hans' => title_zh,
            'en' => title_en
          }.compact
        end

        def from_birth_info(hash, value)
          case value
          when Hash
            hash['birth_year'] = value['year']
            hash['birth_date'] = value['date']
            hash['birth_place'] = value['place']
          else
            hash['birth_year'] = value
          end
        end

        def to_birth_info(_hash, doc)
          return unless birth_year || birth_date || birth_place

          doc['birth_info'] = {
            'year' => birth_year,
            'date' => birth_date,
            'place' => birth_place
          }.compact
        end

        # Check if this is a person
        # @return [Boolean]
        def person?
          type == 'person'
        end

        # Check if this is an organization
        # @return [Boolean]
        def organization?
          type == 'organization'
        end

        # Get primary name in specified language
        # @param lang [String] Language code
        # @return [String, nil]
        def primary_name(lang = nil)
          primary = names.find(&:is_primary)
          return primary&.value if primary

          if lang
            names.find { |n| n.lang == lang }&.value
          else
            names.first&.value
          end
        end

        # Get all names as a simple hash
        # @return [Hash{String => String}]
        def name_hash
          names.each_with_object({}) do |name, hash|
            hash[name.lang || 'value'] = name.value
          end
        end

        # Generate a slug for the entity
        # @return [String]
        def slug
          primary = primary_name('en') || primary_name('zh-Hans') || primary_name
          return id || 'unknown' if primary.nil? || primary.empty?

          # If name contains only non-ASCII characters (like Chinese), use a simplified approach
          if primary.match?(/\p{Han}/) && !primary.match?(/[a-zA-Z]/)
            # For Chinese-only names, use the Chinese characters as-is but limited
            primary.gsub(/\s+/, '-')[0, 50]
          else
            # For names with ASCII, create a URL-safe slug
            slug = primary.downcase
                          .gsub(/[^\w\s-]/, '')
                          .gsub(/\s+/, '-')
                          .gsub(/-+/, '-')
                          .gsub(/^-|-$/, '')
            slug[0, 100] # Limit length
          end
        end

        # Generate entity IRI
        # @return [String]
        def iri
          "https://www.ammitto.org/entity/cn/#{slug}"
        end
      end
    end
  end
end
