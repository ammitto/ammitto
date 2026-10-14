# frozen_string_literal: true

require 'lutaml/model'
require_relative 'ontology/contracts'
require_relative 'ontology/value_objects/legal_citation'
require_relative 'ontology/sanction/sanction_period_modification'
require_relative 'ontology/sanction/official_announcement'

module Ammitto
  # OfficialAnnouncement represents the official announcement of a sanction
  #
  # Links to the original publication with metadata.
  #
  # Legacy facade: its fields are projected from
  # Ontology::Sanction::OfficialAnnouncement (see Ontology::Contracts).
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
    Ontology::Contracts.declare_legacy_attributes(self)

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
