# frozen_string_literal: true

require 'lutaml/model'
require_relative 'notice_reference'
require_relative 'ontology/contracts'
require_relative 'ontology/sanction/status_history'

module Ammitto
  # StatusChange represents a change in sanction status
  #
  # Tracks the history of status changes for a sanction entry,
  # including suspensions, terminations, resumptions, etc.
  #
  # Legacy facade: its fields are projected from
  # Ontology::Sanction::StatusHistory (see Ontology::Contracts). Here
  # +date+ is the raw ISO 8601 string (canonical +timestamp+); the
  # canonical Date is +change_date+.
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

    Ontology::Contracts.declare_legacy_attributes(self)

    json do
      map 'date', to: :date
      map 'fromStatus', to: :from_status
      map 'toStatus', to: :to_status
      map 'reason', to: :reason
      map 'noticeReference', to: :notice_reference
      map 'suspensionEndDate', to: :suspension_end_date
      map 'status', to: :status
      map 'changeDate', to: :change_date
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
