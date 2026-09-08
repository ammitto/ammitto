# frozen_string_literal: true

require 'lutaml/model'
require_relative 'announcement'

module Ammitto
  module Sources
    module Ru
      # For how Russia publishes, the three list types and usage examples,
      # see lib/ammitto/sources/ru.rb.
      # Collection of announcements
      class SanctionsList < Lutaml::Model::Serializable
        attribute :announcements, Announcement, collection: true

        def all_entities
          announcements.flat_map(&:entities)
        end

        def individuals
          all_entities.select(&:person?)
        end

        def organizations
          all_entities.select(&:organization?)
        end
      end
    end
  end
end
