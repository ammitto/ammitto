# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Ru
      # For how Russia publishes, the three list types and usage examples,
      # see lib/ammitto/sources/ru.rb.
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
    end
  end
end
