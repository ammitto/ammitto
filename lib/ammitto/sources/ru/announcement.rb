# frozen_string_literal: true

require 'lutaml/model'
require_relative 'announcement_block'
require_relative 'sanction_details'
require_relative 'list_announcement'

module Ammitto
  module Sources
    module Ru
      # One official announcement from MID, and everyone it names.
      #
      # This is the document data-ru actually stores, one file per
      # announcement with the sanctioned parties inside it. The flat
      # `{ russian_name:, english_name: }` shape is ListAnnouncement's, and
      # no data-ru file uses it.
      #
      # @example Loading one
      #   announcement = Ammitto::Sources::Ru::Announcement.from_yaml(
      #     File.read('sources/announcements/20220413-1.yml')
      #   )
      #   announcement.entities.first.english_name # => "Peter Rey Aguilar"
      #
      class Announcement < Lutaml::Model::Serializable
        attribute :announcement, AnnouncementBlock
        attribute :sanction_details, SanctionDetails

        key_value do
          map 'announcement', to: :announcement
          map 'sanction_details', to: :sanction_details
        end

        # @return [Array<Entity>] the parties named, or none
        def entities
          sanction_details&.entities || []
        end

        # @return [Array<Instrument>] the instruments cited, or none
        def instruments
          sanction_details&.instruments || []
        end

        # @return [String, nil] the announcement's own identifier
        def document_id
          announcement&.document_id
        end

        # @return [String, nil]
        def publish_date
          announcement&.publish_date
        end

        # Ammitto 1.0.0 published this method on this class name, building
        # the flat `{ russian_name:, english_name: }` model. That model is
        # ListAnnouncement now; delegating keeps released callers working.
        # @deprecated Use ListAnnouncement.from_parsed_data
        # @param data [Hash] parsed announcement data
        # @return [ListAnnouncement]
        def self.from_parsed_data(data)
          warn 'Ammitto::Sources::Ru::Announcement.from_parsed_data is ' \
               'deprecated; use ListAnnouncement.from_parsed_data',
               uplevel: 1
          ListAnnouncement.from_parsed_data(data)
        end
      end
    end
  end
end
