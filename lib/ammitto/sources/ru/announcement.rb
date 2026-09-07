# frozen_string_literal: true

require 'lutaml/model'
require_relative 'announcement_block'
require_relative 'sanction_details'

module Ammitto
  module Sources
    module Ru
      # One official announcement from MID, and everyone it names.
      #
      # This is the document data-ru actually stores, one file per
      # announcement with the sanctioned parties inside it. The module's
      # documentation has described a class of this name since before one
      # existed, against a flat `{ russian_name:, english_name: }` shape
      # that the repository has never used.
      #
      # @example Loading one
      #   announcement = Ammitto::Sources::Ru::Announcement.from_yaml(
      #     File.read('sources/announcements/20220413-1.yml')
      #   )
      #   announcement.entities.length # => 398
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
      end
    end
  end
end
