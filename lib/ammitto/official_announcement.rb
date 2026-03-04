# frozen_string_literal: true

require 'lutaml/model'
require_relative 'ontology/value_objects/legal_citation'
require_relative 'ontology/sanction/sanction_period_modification'

module Ammitto
  # OfficialAnnouncement represents the official announcement of a sanction
  #
  # Links to the original publication with metadata.
  #
  # @example Creating an official announcement
  #   OfficialAnnouncement.new(
  #     title: "Designation of Ri Won Ho",
  #     url: "https://www.un.org/securitycouncil/...",
  #     publish_date: "2016-11-30",
  #     author: "UN Security Council Committee"
  #   )
  #
  class OfficialAnnouncement < Lutaml::Model::Serializable
    attribute :id, :string # Unique IRI identifier
    attribute :title, :string
    attribute :url, :string
    attribute :publish_date, :date
    attribute :publish_time, :string        # Time of publication (HH:MM)
    attribute :author, :string              # Who authored/published it
    attribute :author_date, :date           # Date of authorship
    attribute :document_type, :string       # press release, regulation, decision
    attribute :document_id, :string         # Official document ID (e.g., "第4号")
    attribute :signatory, :string           # Person who signed the announcement
    attribute :signatory_title, :string     # Title of the signatory
    attribute :publisher, :string           # Publisher of the announcement
    attribute :authority, :string           # Authority issuing the announcement
    attribute :content, :string             # Full text content of the announcement
    attribute :language, :string            # ISO 639-1 code

    # IDs of SanctionGroup objects created by this announcement
    # @return [Array<String>, nil]
    attribute :sanction_group_ids, :string, collection: true

    # Modifications announced by this announcement
    # @return [Array<SanctionPeriodModification>, nil]
    attribute :modifications, Ontology::Sanction::SanctionPeriodModification,
              collection: true

    # Legal citations from this announcement
    # @return [Array<LegalCitation>, nil]
    attribute :legal_citations, Ontology::ValueObjects::LegalCitation,
              collection: true

    key_value do
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

    # @return [String] display string
    def to_s
      title
    end
  end
end
