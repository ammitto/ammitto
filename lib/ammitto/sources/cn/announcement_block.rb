# frozen_string_literal: true

require 'lutaml/model'
require_relative '../../ontology/value_objects/localized_string'
require_relative 'localized_title_entry'

module Ammitto
  module Sources
    module Cn
      # Announcement block from YAML
      # Handles title in both string and LocalizedString array formats
      class AnnouncementBlock < Lutaml::Model::Serializable
        attribute :title, LocalizedTitleEntry, collection: true
        attribute :url, :string
        attribute :publish_date, :string
        attribute :publish_time, :string
        attribute :authority, :string
        attribute :publisher, :string
        attribute :type, :string
        attribute :document_id, :string
        attribute :signatory, :string
        attribute :signatory_title, :string
        attribute :content, :string
        attribute :lang, :string

        key_value do
          map 'title', to: :title
          map 'url', to: :url
          map 'publish_date', to: :publish_date
          map 'publish_time', to: :publish_time
          map 'authority', to: :authority
          map 'publisher', to: :publisher
          map 'type', to: :type
          map 'document_id', to: :document_id
          map 'signatory', to: :signatory
          map 'signatory_title', to: :signatory_title
          map 'content', to: :content
          map 'lang', to: :lang
        end

        # Get the title as a string (Chinese version)
        # @return [String, nil]
        def primary_title
          chinese_title
        end

        # Get title as LocalizedString array
        # @return [Array<Ammitto::Ontology::ValueObjects::LocalizedString>]
        def localized_titles
          return [] if title.nil? || title.empty?

          title.flat_map do |entry|
            ts = []
            if entry.zh_hans
              ts << Ammitto::Ontology::ValueObjects::LocalizedString.new(
                value: entry.zh_hans,
                language: 'zh',
                script: 'Hani',
                is_primary: true
              )
            end
            if entry.en
              ts << Ammitto::Ontology::ValueObjects::LocalizedString.new(
                value: entry.en,
                language: 'en',
                script: 'Latn',
                is_primary: false
              )
            end
            ts
          end.compact
        end

        # Get Chinese title
        # @return [String, nil]
        def chinese_title
          return nil if title.nil? || title.empty?

          zh_entry = title.find(&:zh_hans)
          zh_entry&.zh_hans
        end

        # Get English title
        # @return [String, nil]
        def english_title
          return nil if title.nil? || title.empty?

          en_entry = title.find(&:en)
          en_entry&.en
        end
      end
    end
  end
end
