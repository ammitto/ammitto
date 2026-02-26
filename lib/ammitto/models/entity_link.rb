# frozen_string_literal: true

module Ammitto
  # EntityLink represents a relationship between entities
  #
  # Used to link entities to related organizations, beneficial owners,
  # vessels, aircraft, etc.
  #
  # @example Creating an entity link
  #   EntityLink.new(
  #     target_id: "https://ammitto.org/entity/abc123",
  #     relationship: "owned_by",
  #     target_name: "ABC Corp"
  #   )
  #
  class EntityLink < Lutaml::Model::Serializable
    # Common relationship types
    RELATIONSHIPS = %w[
      owned_by
      operated_by
      controlled_by
      beneficial_owner_of
      subsidiary_of
      parent_of
      affiliated_with
      related_to
      representative_of
      director_of
      officer_of
      shareholder_of
    ].freeze

    attribute :target_id, :string         # URI of the target entity
    attribute :relationship, :string      # Type of relationship
    attribute :target_name, :string       # Name of target (for display)
    attribute :target_type, :string       # Entity type of target
    attribute :from_date, :date           # Relationship start date
    attribute :to_date, :date             # Relationship end date
    attribute :note, :string              # Additional notes

    json do
      map 'targetId', to: :target_id
      map 'relationship', to: :relationship
      map 'targetName', to: :target_name
      map 'targetType', to: :target_type
      map 'fromDate', to: :from_date
      map 'toDate', to: :to_date
      map 'note', to: :note
    end

    # @return [Boolean] whether the relationship is current
    def current?
      return false if to_date && to_date < Date.today

      true
    end
  end
end
