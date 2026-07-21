# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Data
    module China
      # Represents a Chinese government sanctions announcement
      #
      # @example
      #   announcement = Announcement.from_yaml(yaml_content)
      #   announcement.title # => "关于对...采取反制裁措施的决定"
      #   announcement.publish_date # => Date.new(2022, 12, 23)
      #
      class Announcement < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :title, :string
        attribute :url, :string
        attribute :publish_date, :date
        attribute :publish_time, :string
        attribute :document_id, :string
        attribute :document_type, :string
        attribute :authority, :string
        attribute :publisher, :string
        attribute :signatory, :string
        attribute :signatory_title, :string
        attribute :content, :string
        attribute :lang, :string, default: 'zh-Hans'

        # Source-specific metadata
        attribute :source, :string # 'mofcom', 'mfa'
        attribute :list_type, :string # 'anti-sanction-list', 'unreliable-entity-list', etc.

        yaml do
          root 'announcement'
          map 'id', to: :id
          map 'title', to: :title
          map 'url', to: :url
          map 'publish_date', to: :publish_date
          map 'publish_time', to: :publish_time
          map 'document_id', to: :document_id
          map 'document_type', to: :document_type
          map 'authority', to: :authority
          map 'publisher', to: :publisher
          map 'signatory', to: :signatory
          map 'signatory_title', to: :signatory_title
          map 'content', to: :content
          map 'lang', to: :lang
        end

        # Generate unique identifier for this announcement
        # @return [String] IRI identifier
        def iri
          "https://www.ammitto.org/announcement/cn/#{id}"
        end

        # Publication datetime (combines date and time if available)
        # @return [DateTime, nil]
        def published_at
          return nil unless publish_date

          if publish_time
            DateTime.new(
              publish_date.year,
              publish_date.month,
              publish_date.day,
              *publish_time.split(':').map(&:to_i)
            )
          else
            DateTime.new(publish_date.year, publish_date.month, publish_date.day)
          end
        rescue StandardError
          nil
        end
      end
    end
  end
end
