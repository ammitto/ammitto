# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Cn
      # China Sanctions List (HTML announcements)
      # Source: MOFCOM (商务部) and MFA (外交部)
      # URLs: mofcom.gov.cn, mfa.gov.cn
      #
      # China has multiple list types:
      # 1. 不可靠实体清单 (Unreliable Entity List) - MOFCOM
      # 2. 反制裁清单 (Anti-Sanctions List) - MFA
      # 3. 出口管制管控名单 (Export Control List) - MOFCOM
      #
      # Data is published as HTML announcements, not structured XML/JSON

      # Sanctioned Entity from China announcements
      class SanctionedEntity < Lutaml::Model::Serializable
        attribute :chinese_name, :string
        attribute :english_name, :string
        attribute :entity_type, :string # 'person' or 'organization'
        attribute :list_type, :string # 'unreliable_entity', 'anti_sanctions', 'export_control'
        attribute :announcement_number, :string # e.g., "2025年 第5号"
        attribute :announcement_date, :string
        attribute :effective_date, :string
        attribute :reason, :string
        attribute :measures, :string, collection: true
        attribute :legal_basis, :string, collection: true
        attribute :source_url, :string

        # For persons
        attribute :date_of_birth, :string
        attribute :nationality, :string
        attribute :gender, :string
        attribute :title, :string

        # For organizations
        attribute :registration_number, :string
        attribute :country_of_registration, :string

        yaml do
          map 'chinese_name', to: :chinese_name
          map 'english_name', to: :english_name
          map 'entity_type', to: :entity_type
          map 'list_type', to: :list_type
          map 'announcement_number', to: :announcement_number
          map 'announcement_date', to: :announcement_date
          map 'effective_date', to: :effective_date
          map 'reason', to: :reason
          map 'measures', to: :measures
          map 'legal_basis', to: :legal_basis
          map 'source_url', to: :source_url
          map 'date_of_birth', to: :date_of_birth
          map 'nationality', to: :nationality
          map 'gender', to: :gender
          map 'title', to: :title
          map 'registration_number', to: :registration_number
          map 'country_of_registration', to: :country_of_registration
        end

        def full_name
          english_name || chinese_name
        end

        def person?
          entity_type == 'person'
        end

        def organization?
          entity_type == 'organization'
        end
      end

      # Announcement containing multiple sanctioned entities
      class Announcement < Lutaml::Model::Serializable
        attribute :number, :string
        attribute :date, :string
        attribute :title, :string
        attribute :issuing_authority, :string # MOFCOM or MFA
        attribute :list_type, :string
        attribute :legal_basis, :string, collection: true
        attribute :reason, :string
        attribute :measures, :string, collection: true
        attribute :effective_date, :string
        attribute :source_url, :string
        attribute :entities, SanctionedEntity, collection: true

        # Parse entities from announcement text
        # This is called after HTML parsing extracts the relevant fields
        def self.from_parsed_data(data)
          announcement = new(
            number: data[:announcement_number],
            date: data[:date],
            title: data[:title],
            issuing_authority: data[:issuing_authority],
            list_type: data[:list_type],
            legal_basis: data[:legal_basis] || [],
            reason: data[:reason],
            measures: data[:measures] || [],
            effective_date: data[:effective_date],
            source_url: data[:source_url],
            entities: []
          )

          # Parse entities from the announcement
          (data[:entities] || []).each do |entity_data|
            announcement.entities << SanctionedEntity.new(
              chinese_name: entity_data[:chinese_name],
              english_name: entity_data[:english_name],
              entity_type: entity_data[:entity_type] || 'organization',
              list_type: announcement.list_type,
              announcement_number: announcement.number,
              announcement_date: announcement.date,
              effective_date: announcement.effective_date,
              reason: announcement.reason,
              measures: announcement.measures,
              legal_basis: announcement.legal_basis,
              source_url: announcement.source_url,
              date_of_birth: entity_data[:date_of_birth],
              nationality: entity_data[:nationality],
              gender: entity_data[:gender],
              title: entity_data[:title],
              registration_number: entity_data[:registration_number],
              country_of_registration: entity_data[:country_of_registration]
            )
          end

          announcement
        end
      end

      # Collection of announcements
      class SanctionsList < Lutaml::Model::Serializable
        attribute :announcements, Announcement, collection: true

        # Get all entities from all announcements
        def all_entities
          announcements.flat_map(&:entities)
        end

        # Get individuals only
        def individuals
          all_entities.select(&:person?)
        end

        # Get organizations only
        def organizations
          all_entities.select(&:organization?)
        end
      end
    end
  end
end
