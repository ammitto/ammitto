# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Cn
      # Individual modification from YAML
      class Modification < Lutaml::Model::Serializable
        attribute :action, :string # 'suspend' or 'stop'
        attribute :target_announcement_id, :string
        attribute :target_announcement_date, :string
        attribute :effective_date, :string
        attribute :effective_time, :string
        attribute :until_date, :string
        attribute :until_time, :string
        attribute :duration_days, :integer
        attribute :affected_entity_names, :string, collection: true
        attribute :notes, :string

        key_value do
          map 'action', to: :action
          map 'target_announcement_id', to: :target_announcement_id
          map 'target_announcement_date', to: :target_announcement_date
          map 'effective_date', to: :effective_date
          map 'effective_time', to: :effective_time
          map 'until_date', to: :until_date
          map 'until_time', to: :until_time
          map 'duration_days', to: :duration_days
          map 'affected_entity_names', to: :affected_entity_names
          map 'notes', to: :notes
        end

        # Get affected entity count
        # @return [Integer]
        def affected_entity_count
          affected_entity_names&.size || 0
        end
      end

      # Instrument reference from YAML (reused for modifications)
      class ModificationInstrument < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :law, :string
        attribute :articles, :string, collection: true

        key_value do
          map 'id', to: :id
          map 'law', to: :law
          map 'articles', to: :articles
        end
      end

      # Modification block from YAML
      class ModificationBlock < Lutaml::Model::Serializable
        attribute :instruments, ModificationInstrument, collection: true
        attribute :modifications, Modification, collection: true

        key_value do
          map 'instruments', to: :instruments
          map 'modifications', to: :modifications
        end
      end

      # Localized title entry from YAML (for modification announcements)
      class ModificationLocalizedTitleEntry < Lutaml::Model::Serializable
        attribute :zh_hans, :string # Maps from zh-Hans in YAML
        attribute :en, :string

        key_value do
          map 'zh-Hans', to: :zh_hans
          map 'en', to: :en
        end
      end

      # Modification announcement block from YAML
      class ModificationAnnouncementBlock < Lutaml::Model::Serializable
        attribute :title, :string # Can be string or array - handled via custom accessor
        attribute :url, :string
        attribute :publish_date, :string
        attribute :publish_time, :string
        attribute :authority, :string
        attribute :publisher, :string
        attribute :content, :string
        attribute :lang, :string

        # Raw title value (can be string or array)
        attr_reader :raw_title

        key_value do
          map 'title', to: :title
          map 'url', to: :url
          map 'publish_date', to: :publish_date
          map 'publish_time', to: :publish_time
          map 'authority', to: :authority
          map 'publisher', to: :publisher
          map 'content', to: :content
          map 'lang', to: :lang
        end

        # Custom setter to handle both string and array title formats
        def title=(value)
          @raw_title = value
          @title = if value.is_a?(Array)
                     # Extract Chinese title from array format
                     value.first&.dig('zh-Hans') || value.first&.dig(:'zh-Hans')
                   else
                     value
                   end
        end

        # Get Chinese title
        # @return [String, nil]
        def chinese_title
          return @title if @raw_title.is_a?(String)
          return nil unless @raw_title.is_a?(Array)

          entry = @raw_title.first
          return nil unless entry

          entry['zh-Hans'] || entry[:'zh-Hans']
        end

        # Get English title
        # @return [String, nil]
        def english_title
          return nil if @raw_title.is_a?(String)
          return nil unless @raw_title.is_a?(Array)

          entry = @raw_title.first
          return nil unless entry

          entry['en'] || entry[:en]
        end
      end

      # Source model for data-cn YAML measure modification format
      #
      # This model matches the schema defined in data-cn/schemas/cn-measure-modification.yml
      # and is used to parse YAML files from sources/sanction-updates/
      #
      # @example Parsing a modification YAML file
      #   data = YAML.load_file('sources/sanction-updates/20250514.yml')
      #   modification = MeasureModification.from_hash(data)
      #   modification.measure_modifications.modifications.each do |mod|
      #     puts "#{mod.action} - #{mod.target_announcement_id}"
      #   end
      #
      class MeasureModification < Lutaml::Model::Serializable
        attribute :announcement, ModificationAnnouncementBlock
        attribute :measure_modifications, ModificationBlock

        key_value do
          map 'announcement', to: :announcement
          map 'measure_modifications', to: :measure_modifications
        end

        # Get all modifications
        # @return [Array<Modification>]
        def modifications
          measure_modifications&.modifications || []
        end

        # Get all instruments
        # @return [Array<ModificationInstrument>]
        def instruments
          measure_modifications&.instruments || []
        end
      end
    end
  end
end
