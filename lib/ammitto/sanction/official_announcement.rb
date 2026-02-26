# frozen_string_literal: true

module Ammitto
  # OfficialAnnouncement represents the official announcement of a sanction
  #
  # Links to the original publication with metadata.
  #
  # @example Creating an official announcement
  #   OfficialAnnouncement.new(
  #     title: "Designation of Ri Won Ho",
  #     url: "https://www.un.org/securitycouncil/...",
  #     published_date: "2016-11-30",
  #     author: "UN Security Council Committee"
  #   )
  #
  class OfficialAnnouncement < Lutaml::Model::Serializable
    attribute :title, :string
    attribute :url, :string
    attribute :published_date, :date
    attribute :author, :string           # Who authored/published it
    attribute :author_date, :date        # Date of authorship
    attribute :document_type, :string    # press release, regulation, decision
    attribute :language, :string         # ISO 639-1 code

    json do
      map 'title', to: :title
      map 'url', to: :url
      map 'publishedDate', to: :published_date
      map 'author', to: :author
      map 'authorDate', to: :author_date
      map 'documentType', to: :document_type
      map 'language', to: :language
    end

    # @return [String] display string
    def to_s
      title
    end
  end
end
