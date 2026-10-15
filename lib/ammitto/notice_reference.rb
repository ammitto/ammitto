# frozen_string_literal: true

require 'lutaml/model'
require_relative 'ontology/contracts'
require_relative 'ontology/value_objects/notice_reference'

module Ammitto
  # NoticeReference represents a reference to an official notice
  #
  # Used to track the official document that caused a status change.
  #
  # Legacy facade: its fields are projected from
  # Ontology::ValueObjects::NoticeReference (see Ontology::Contracts).
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
    Ontology::Contracts.declare_legacy_attributes(self)

    json do
      map 'noticeNumber', to: :notice_number
      map 'noticeDate', to: :notice_date
      map 'noticeTitle', to: :notice_title
      map 'noticeUrl', to: :notice_url
    end
  end
end
