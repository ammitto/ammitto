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
        attribute :type, :string
        attribute :document_id, :string
        attribute :signatory, :string
        attribute :signatory_title, :string

        # Raw title value (can be string or array)
        attr_reader :raw_title

        key_value do
          # data-cn writes the title as a localized list as well as a bare
          # string; reading YAML through the setter below takes either, which
          # a plain :string mapping would refuse for the list.
          map 'title', to: :title, with: { from: :title_from_key_value, to: :title_to_key_value }
          map 'url', to: :url
          map 'publish_date', to: :publish_date
          map 'publish_time', to: :publish_time
          map 'authority', to: :authority
          map 'publisher', to: :publisher
          map 'content', to: :content
          map 'lang', to: :lang
          map 'type', to: :type
          map 'document_id', to: :document_id
          map 'signatory', to: :signatory
          map 'signatory_title', to: :signatory_title
        end

        def title_from_key_value(model, value)
          model.title = value
        end

        def title_to_key_value(model, doc)
          doc['title'] = model.raw_title unless model.raw_title.nil?
        end

        # Custom setter to handle both string and array title formats
        def title=(value)
          @raw_title = value
          @title = value.is_a?(Array) ? localized_title('zh-Hans') : value
        end

        # Get Chinese title
        # @return [String, nil]
        def chinese_title
          return @title if @raw_title.is_a?(String)
          return nil unless @raw_title.is_a?(Array)

          localized_title('zh-Hans')
        end

        # Get English title
        # @return [String, nil]
        def english_title
          return nil if @raw_title.is_a?(String)
          return nil unless @raw_title.is_a?(Array)

          localized_title('en')
        end

        private

        # data-cn writes one map holding every language as well as one map
        # per language, so each language is looked up across all entries.
        def localized_title(lang)
          @raw_title.each do |entry|
            next unless entry.is_a?(Hash)

            value = entry[lang] || entry[lang.to_sym]
            return value if value
          end
          nil
        end
      end
    end
  end
end
