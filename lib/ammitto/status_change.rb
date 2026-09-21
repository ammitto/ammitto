# frozen_string_literal: true

require 'lutaml/model'
require_relative 'notice_reference'

module Ammitto
  # StatusChange represents a change in sanction status
  #
  # Tracks the history of status changes for a sanction entry,
  # including suspensions, terminations, resumptions, etc.
  #
  # @example Creating a status change
  #   StatusChange.new(
  #     date: "2025-05-14",
  #     from_status: "active",
  #     to_status: "suspended",
  #     reason: "Temporary suspension per notice",
  #     notice_reference: NoticeReference.new(...)
  #   )
  #
  class StatusChange < Lutaml::Model::Serializable
    # Sanction status values
    STATUSES = %w[
      active
      suspended
      resumed
      terminated
      delisted
      expired
      deceased
    ].freeze

    attribute :date, :string # ISO 8601 datetime string
    attribute :from_status, :string
    attribute :to_status, :string
    attribute :reason, :string
    attribute :notice_reference, NoticeReference
    attribute :suspension_end_date, :date # For suspended status

    json do
      map 'date', to: :date
      map 'fromStatus', to: :from_status
      map 'toStatus', to: :to_status
      map 'reason', to: :reason
      map 'noticeReference', to: :notice_reference
      map 'suspensionEndDate', to: :suspension_end_date
    end

    # @return [Boolean] whether this is a suspension
    def suspension?
      to_status == 'suspended'
    end

    # @return [Boolean] whether this is a termination
    def termination?
      to_status == 'terminated'
    end

    # @return [Boolean] whether this is a delisting
    def delisting?
      to_status == 'delisted'
    end
  end
end
