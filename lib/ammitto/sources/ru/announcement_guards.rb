# frozen_string_literal: true

require_relative 'document_id_guard'
require_relative 'lost_party_guard'
require_relative 'party_type_guard'

module Ammitto
  module Sources
    module Ru
      # Every check that refuses an announcement before anything is built
      # from it, in one place so the transformer asks once.
      module AnnouncementGuards
        include DocumentIdGuard
        include LostPartyGuard
        include PartyTypeGuard

        # @param announcement [Announcement] the parsed announcement
        # @raise [Ammitto::ParseError] when any guard refuses it
        # @return [void]
        def refuse_unreadable(announcement)
          refuse_without_document_id(announcement)
          refuse_if_parties_were_lost(announcement)
          refuse_untyped_parties(announcement)
        end
      end
    end
  end
end
