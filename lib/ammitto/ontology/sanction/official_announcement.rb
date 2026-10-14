# frozen_string_literal: true

require 'lutaml/model'
require_relative '../value_objects/immutable'
require_relative '../value_objects/legal_citation'
require_relative 'sanction_period_modification'

module Ammitto
  module Ontology
    module Sanction
      # The official announcement that published a sanction
      #
      # @example
      #   OfficialAnnouncement.new(
      #     title: "Designation of Ri Won Ho",
      #     url: "https://www.un.org/securitycouncil/...",
      #     publish_date: Date.new(2016, 11, 30),
      #     author: "UN Security Council Committee"
      #   )
      #
      class OfficialAnnouncementModel < Lutaml::Model::Serializable
        # Unique IRI identifier
        # @return [String, nil]
        attribute :id, :string

        # @return [String, nil]
        attribute :title, :string

        # @return [String, nil]
        attribute :url, :string

        # @return [Date, nil]
        attribute :publish_date, :date

        # Time of publication as the source wrote it (HH:MM)
        # @return [String, nil]
        attribute :publish_time, :string

        # Who authored or published it
        # @return [String, nil]
        attribute :author, :string

        # Date of authorship
        # @return [Date, nil]
        attribute :author_date, :date

        # Press release, regulation, decision, ...
        # @return [String, nil]
        attribute :document_type, :string

        # Official document number (e.g. "第4号")
        # @return [String, nil]
        attribute :document_id, :string

        # Person who signed the announcement
        # @return [String, nil]
        attribute :signatory, :string

        # Title of the signatory
        # @return [String, nil]
        attribute :signatory_title, :string

        # @return [String, nil]
        attribute :publisher, :string

        # Authority issuing the announcement
        # @return [String, nil]
        attribute :authority, :string

        # Full text of the announcement
        # @return [String, nil]
        attribute :content, :string

        # ISO 639-1 code
        # @return [String, nil]
        attribute :language, :string

        # IDs of the SanctionGroup objects this announcement created
        # @return [Array<String>, nil]
        attribute :sanction_group_ids, :string, collection: true

        # Modifications this announcement made
        # @return [Array<SanctionPeriodModification>, nil]
        attribute :modifications, SanctionPeriodModification, collection: true

        # Legal citations in this announcement
        # @return [Array<ValueObjects::LegalCitation>, nil]
        attribute :legal_citations, ValueObjects::LegalCitation, collection: true

        key_value do
          map :id, to: :id
          map :title, to: :title
          map :url, to: :url
          map :publish_date, to: :publish_date
          map :publish_time, to: :publish_time
          map :author, to: :author
          map :author_date, to: :author_date
          map :document_type, to: :document_type
          map :document_id, to: :document_id
          map :signatory, to: :signatory
          map :signatory_title, to: :signatory_title
          map :publisher, to: :publisher
          map :authority, to: :authority
          map :content, to: :content
          map :language, to: :language
          map :sanction_group_ids, to: :sanction_group_ids
          map :modifications, to: :modifications
          map :legal_citations, to: :legal_citations
        end
      end
      private_constant :OfficialAnnouncementModel

      class OfficialAnnouncement < OfficialAnnouncementModel
        include ValueObjects::Immutable
      end
    end
  end
end
