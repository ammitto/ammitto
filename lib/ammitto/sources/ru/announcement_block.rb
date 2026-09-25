# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Ru
      # The announcement's own metadata.
      #
      # `title` and `content` are hashes keyed by language. data-cn writes
      # its title as a list of single-language maps and its content as a
      # bare string; data-ru writes both as `{ru:, en:}`. The two source
      # repositories genuinely differ here, so the models do too.
      class AnnouncementBlock < Lutaml::Model::Serializable
        attribute :title, :hash
        attribute :url, :string
        attribute :publish_date, :string
        attribute :publish_time, :string
        attribute :authority, :string
        attribute :publisher, :string
        attribute :type, :string
        attribute :document_id, :string
        attribute :signatory, :string
        attribute :content, :hash
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
          map 'content', to: :content
          map 'lang', to: :lang
        end
      end
    end
  end
end
