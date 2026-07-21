# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Data
    module Japan
      module Mof
        # Represents a Japan MOF sanctions announcement
        #
        # @example
        #   announcement = Announcement.new(
        #     title: { ja: 'ロシア連邦(個人)', en: 'Russian Federation (Individuals)' },
        #     url: 'https://www.mof.go.jp/...',
        #     publish_date: Date.new(2026, 3, 5),
        #     authority: 'jp/mof'
        #   )
        #
        class Announcement < Lutaml::Model::Serializable
          # Title as multilingual hash
          attribute :title, :hash

          # URLs
          attribute :url, :string
          attribute :source_url, :string
          attribute :source_file, :string

          # Dates
          attribute :publish_date, :date

          # Authority
          attribute :authority, :string
          attribute :publisher, :string

          # Document type
          attribute :type, :string

          yaml do
            map 'title', to: :title
            map 'url', to: :url
            map 'source_url', to: :source_url
            map 'source_file', to: :source_file
            map 'publish_date', to: :publish_date
            map 'authority', to: :authority
            map 'publisher', to: :publisher
            map 'type', to: :type
          end

          # Add title in a specific language
          # @param lang [String] Language code
          # @param value [String] Title value
          def add_title(lang, value)
            return if value.nil? || value.to_s.strip.empty?

            self.title ||= {}
            self.title[lang.to_s] = value.to_s.strip
          end

          # Convert to hash for YAML serialization
          # @return [Hash]
          def to_hash
            hash = {}

            # Title - convert to array of single-key hashes if needed
            if title&.any?
              hash['title'] = if title.keys.length == 1
                                title
                              else
                                title.map { |k, v| { k => v } }
                              end
            end

            hash['url'] = url if url
            hash['source_url'] = source_url if source_url
            hash['source_file'] = source_file if source_file
            hash['publish_date'] = publish_date&.to_s if publish_date
            hash['authority'] = authority if authority
            hash['publisher'] = publisher if publisher
            hash['type'] = type if type

            hash.compact
          end
        end
      end
    end
  end
end
