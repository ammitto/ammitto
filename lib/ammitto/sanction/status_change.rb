# frozen_string_literal: true

module Ammitto
  # NoticeReference represents a reference to an official notice
  #
  # Used to track the official document that caused a status change.
  #
  # @example Creating a notice reference
  #   NoticeReference.new(
  #     notice_number: "〔2025〕7號",
  #     notice_date: "2025-05-14",
  #     notice_title: "Suspension Notice",
  #     notice_url: "https://example.gov/notice/2025-7"
  #   )
  #
  class NoticeReference < Lutaml::Model::Serializable
    attribute :notice_number, :string # E.g., "〔2025〕7號"
    attribute :notice_date, :date
    attribute :notice_title, :string
    attribute :notice_url, :string

    json do
      map 'noticeNumber', to: :notice_number
      map 'noticeDate', to: :notice_date
      map 'noticeTitle', to: :notice_title
      map 'noticeUrl', to: :notice_url
    end
  end

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
