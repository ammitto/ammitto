# frozen_string_literal: true

require 'lutaml/model'
require_relative '../../ontology/value_objects/localized_string'
require_relative '../../ontology/value_objects/legal_citation'

module Ammitto
  module Sources
    module Cn
      # Measure from YAML
      class Measure < Lutaml::Model::Serializable
        attribute :type, :string, collection: true
        attribute :zh_hans, :string # Maps from zh-Hans in YAML
        attribute :en, :string

        key_value do
          map 'type', to: :type
          map 'zh-Hans', to: :zh_hans
          map 'en', to: :en
        end

        # Get Chinese description
        # @return [String, nil]
        def chinese_description
          zh_hans
        end

        # Get English description
        # @return [String, nil]
        def english_description
          en
        end
      end

      # Instrument reference from YAML
      class Instrument < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :law, :string
        attribute :articles, :string, collection: true

        key_value do
          map 'id', to: :id
          map 'law', to: :law
          map 'articles', to: :articles
        end

        # Convert to LegalCitation
        # @param instrument_id [String] the IRI of the LegalInstrument
        # @return [Ammitto::Ontology::ValueObjects::LegalCitation]
        def to_legal_citation(instrument_id:)
          Ammitto::Ontology::ValueObjects::LegalCitation.new(
            legal_instrument_id: instrument_id,
            articles: articles,
            citation_type: 'legal_basis'
          )
        end
      end

      # Localized title entry from YAML
      class LocalizedTitleEntry < Lutaml::Model::Serializable
        attribute :zh_hans, :string # Maps from zh-Hans in YAML
        attribute :en, :string

        key_value do
          map 'zh-Hans', to: :zh_hans
          map 'en', to: :en
        end
      end

      # Entity from YAML
      class Entity < Lutaml::Model::Serializable
        attribute :name, :hash # { 'zh-Hans' => '...', 'en' => '...' }
        attribute :type, :string # 'organization' or 'individual'
        attribute :effective_date, :string
        attribute :effective_time, :string
        attribute :sanction_list, :string
        attribute :reason, :hash, collection: true # [{ 'zh-Hans' => '...', 'en' => '...' }]
        attribute :measures, Measure, collection: true
        attribute :title, :hash # { 'zh-Hans' => '...', 'en' => '...' }
        attribute :gender, :string

        key_value do
          map 'name', to: :name
          map 'type', to: :type
          map 'effective_date', to: :effective_date
          map 'effective_time', to: :effective_time
          map 'sanction_list', to: :sanction_list
          map 'reason', to: :reason
          map 'measures', to: :measures
          map 'title', to: :title
          map 'gender', to: :gender
        end

        # Get Chinese name
        # @return [String, nil]
        def chinese_name
          name&.dig('zh-Hans')
        end

        # Get English name
        # @return [String, nil]
        def english_name
          name&.dig('en')
        end

        # Check if this is a person
        # @return [Boolean]
        def person?
          type == 'individual'
        end

        # Check if this is an organization
        # @return [Boolean]
        def organization?
          type == 'organization'
        end

        # Get list type code
        # @return [String]
        def list_type_code
          case sanction_list
          when '反制裁清单'
            'anti_sanctions'
          when '不可靠实体清单'
            'unreliable_entity'
          when '出口管制管控名单'
            'export_control'
          else
            'unknown'
          end
        end
      end

      # Sanction details block from YAML
      class SanctionDetails < Lutaml::Model::Serializable
        attribute :instruments, Instrument, collection: true
        attribute :entities, Entity, collection: true

        key_value do
          map 'instruments', to: :instruments
          map 'entities', to: :entities
        end
      end

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

      # Source model for data-cn YAML announcement format
      #
      # This model matches the schema defined in data-cn/schemas/cn-announcement.yml
      # and is used to parse YAML files from sources/sanction-lists/
      #
      # @example Parsing a YAML file
      #   data = YAML.load_file('sources/sanction-lists/anti-sanction-list/20221223.yml')
      #   announcement = Announcement.from_hash(data)
      #   announcement.sanction_details.entities.each do |entity|
      #     puts entity.name['zh-Hans']
      #   end
      #
      class Announcement < Lutaml::Model::Serializable
        attribute :announcement, AnnouncementBlock
        attribute :sanction_details, SanctionDetails

        key_value do
          map 'announcement', to: :announcement
          map 'sanction_details', to: :sanction_details
        end

        # Get all entities from this announcement
        # @return [Array<Entity>]
        def entities
          sanction_details&.entities || []
        end

        # Get all instruments from this announcement
        # @return [Array<Instrument>]
        def instruments
          sanction_details&.instruments || []
        end

        # Check if this is a multi-entity announcement
        # @return [Boolean]
        def multi_entity?
          entities.count > 1
        end
      end
    end
  end
end
