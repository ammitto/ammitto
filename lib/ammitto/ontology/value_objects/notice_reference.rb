# frozen_string_literal: true

require 'lutaml/model'
require_relative 'immutable'

module Ammitto
  module Ontology
    module ValueObjects
      # Reference to the official notice behind a status change
      #
      # @example
      #   NoticeReference.new(
      #     notice_number: "〔2025〕7號",
      #     notice_date: Date.new(2025, 5, 14),
      #     notice_title: "Suspension Notice",
      #     notice_url: "https://example.gov/notice/2025-7"
      #   )
      #
      class NoticeReferenceModel < Lutaml::Model::Serializable
        # Notice number as published (e.g. "〔2025〕7號")
        # @return [String, nil]
        attribute :notice_number, :string

        # Publication date of the notice
        # @return [Date, nil]
        attribute :notice_date, :date

        # Title of the notice
        # @return [String, nil]
        attribute :notice_title, :string

        # URL of the notice
        # @return [String, nil]
        attribute :notice_url, :string

        key_value do
          map :notice_number, to: :notice_number
          map :notice_date, to: :notice_date
          map :notice_title, to: :notice_title
          map :notice_url, to: :notice_url
        end
      end
      private_constant :NoticeReferenceModel

      class NoticeReference < NoticeReferenceModel
        include Immutable
      end
    end
  end
end
