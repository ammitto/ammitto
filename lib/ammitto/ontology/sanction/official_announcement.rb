# frozen_string_literal: true

require_relative 'official_announcement_model'

module Ammitto
  module Ontology
    module Sanction
      class OfficialAnnouncement < OfficialAnnouncementModel
        include ValueObjects::Immutable
      end
    end
  end
end
