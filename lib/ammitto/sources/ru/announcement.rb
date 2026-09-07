# frozen_string_literal: true

require 'lutaml/model'
require_relative 'sanctioned_entity'

module Ammitto
  module Sources
    module Ru
      # For how Russia publishes, the three list types and usage examples,
      # see lib/ammitto/sources/ru.rb.
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
    end
  end
end
