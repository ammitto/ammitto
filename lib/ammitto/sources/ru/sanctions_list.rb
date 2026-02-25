# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Ru
      # Russia Sanctions List (HTML announcements)
      # Source: Ministry of Foreign Affairs (MID - mid.ru)
      #
      # Russia maintains:
      # 1. Стоп-лист (Stop-list) - Entry bans on foreign persons
      # 2. Central Bank sanctions
      # 3. Government decrees (Постановления)
      #
      # Data is published as HTML announcements

      # Sanctioned Entity from Russia announcements
      class SanctionedEntity < Lutaml::Model::Serializable
        attribute :russian_name, :string # Cyrillic
        attribute :english_name, :string
        attribute :entity_type, :string # 'person' or 'organization'
        attribute :list_type, :string # 'stop_list', 'financial_sanctions', etc.
        attribute :announcement_number, :string
        attribute :announcement_date, :string
        attribute :effective_date, :string
        attribute :reason, :string
        attribute :measures, :string, collection: true
        attribute :source_url, :string

        # For persons
        attribute :date_of_birth, :string
        attribute :nationality, :string
        attribute :title, :string
        attribute :affiliation, :string # Organization they belong to

        # For organizations
        attribute :country, :string
        attribute :industry, :string

        yaml do
          map 'russian_name', to: :russian_name
          map 'english_name', to: :english_name
          map 'entity_type', to: :entity_type
          map 'list_type', to: :list_type
          map 'announcement_number', to: :announcement_number
          map 'announcement_date', to: :announcement_date
          map 'effective_date', to: :effective_date
          map 'reason', to: :reason
          map 'measures', to: :measures
          map 'source_url', to: :source_url
          map 'date_of_birth', to: :date_of_birth
          map 'nationality', to: :nationality
          map 'title', to: :title
          map 'affiliation', to: :affiliation
          map 'country', to: :country
          map 'industry', to: :industry
        end

        def full_name
          english_name || russian_name
        end

        def person?
          entity_type == 'person'
        end

        def organization?
          entity_type == 'organization'
        end
      end

      # Announcement containing sanctioned entities
      class Announcement < Lutaml::Model::Serializable
        attribute :number, :string
        attribute :date, :string
        attribute :title, :string
        attribute :issuing_authority, :string # MID, CBR, Government
        attribute :list_type, :string
        attribute :reason, :string
        attribute :measures, :string, collection: true
        attribute :effective_date, :string
        attribute :source_url, :string
        attribute :entities, SanctionedEntity, collection: true

        def self.from_parsed_data(data)
          announcement = new(
            number: data[:number],
            date: data[:date],
            title: data[:title],
            issuing_authority: data[:issuing_authority],
            list_type: data[:list_type],
            reason: data[:reason],
            measures: data[:measures] || [],
            effective_date: data[:effective_date],
            source_url: data[:source_url],
            entities: []
          )

          (data[:entities] || []).each do |entity_data|
            announcement.entities << SanctionedEntity.new(
              russian_name: entity_data[:russian_name],
              english_name: entity_data[:english_name],
              entity_type: entity_data[:entity_type] || 'person',
              list_type: announcement.list_type,
              announcement_number: announcement.number,
              announcement_date: announcement.date,
              effective_date: announcement.effective_date,
              reason: announcement.reason,
              measures: announcement.measures,
              source_url: announcement.source_url,
              date_of_birth: entity_data[:date_of_birth],
              nationality: entity_data[:nationality],
              title: entity_data[:title],
              affiliation: entity_data[:affiliation],
              country: entity_data[:country],
              industry: entity_data[:industry]
            )
          end

          announcement
        end
      end

      # Collection of announcements
      class SanctionsList < Lutaml::Model::Serializable
        attribute :announcements, Announcement, collection: true

        def all_entities
          announcements.flat_map(&:entities)
        end

        def individuals
          all_entities.select(&:person?)
        end

        def organizations
          all_entities.select(&:organization?)
        end
      end
    end
  end
end
