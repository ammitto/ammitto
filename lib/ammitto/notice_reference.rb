# frozen_string_literal: true

require 'lutaml/model'

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
end
