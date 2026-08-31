# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Cn
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
    end
  end
end
