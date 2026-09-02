# frozen_string_literal: true

require 'lutaml/model'
require_relative 'sanction_details'
require_relative 'announcement_block'

module Ammitto
  module Sources
    module Cn
      # Source model for data-cn YAML announcement format
      #
      # This model matches the schema defined in data-cn/schemas/cn-announcement.yml
      # and is used to parse YAML files from sources/sanction-lists/
      #
      # @example Parsing a YAML file
      #   data = YAML.load_file('sources/sanction-lists/anti-sanction-list/20221223.yml')
      #   announcement = Announcement.from_hash(data)
      #   announcement.sanction_details.entities.each do |entity|
      #     puts entity.name['zh-Hans']
      #   end
      #
      class Announcement < Lutaml::Model::Serializable
        attribute :announcement, AnnouncementBlock
        attribute :sanction_details, SanctionDetails

        key_value do
          map 'announcement', to: :announcement
          map 'sanction_details', to: :sanction_details
        end

        # Get all entities from this announcement
        # @return [Array<Entity>]
        def entities
          sanction_details&.entities || []
        end

        # Get all instruments from this announcement
        # @return [Array<Instrument>]
        def instruments
          sanction_details&.instruments || []
        end

        # Check if this is a multi-entity announcement
        # @return [Boolean]
        def multi_entity?
          entities.count > 1
        end
      end
    end
  end
end
