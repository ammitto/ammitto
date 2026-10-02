# frozen_string_literal: true

require_relative '../../error'

module Ammitto
  module Sources
    module Ru
      # Refuses an announcement naming a party whose type it cannot read.
      #
      # A party becomes a person or an organization, and the two carry
      # different fields. A missing or unrecognised type gives no ground
      # for either, so publishing one would be a guess presented as the
      # source's statement.
      module PartyTypeGuard
        # The party types data-ru writes.
        PARTY_TYPES = %w[individual organization].freeze

        # @param announcement [Announcement] the parsed announcement
        # @raise [Ammitto::ParseError] when any party's type is missing or
        #   not one of PARTY_TYPES
        # @return [void]
        def refuse_untyped_parties(announcement)
          untyped = announcement.entities.reject do |entity|
            PARTY_TYPES.include?(entity.type)
          end
          return if untyped.empty?

          raise Ammitto::ParseError.new(
            "ru announcement #{announcement.document_id.inspect} names " \
            "#{untyped.length} part#{untyped.length == 1 ? 'y' : 'ies'} " \
            "with no readable type (#{untyped.map(&:type).uniq.inspect}); " \
            "expected one of #{PARTY_TYPES.inspect}",
            format: :yaml
          )
        end
      end
    end
  end
end
