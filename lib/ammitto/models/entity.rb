# frozen_string_literal: true

module Ammitto
  # Entity is the abstract base class for all sanctioned entities
  #
  # This class should not be instantiated directly. Use one of the
  # subclasses: PersonEntity, OrganizationEntity, VesselEntity, or AircraftEntity.
  #
  # @example Creating a person entity
  #   PersonEntity.new(
  #     id: "https://ammitto.org/entity/123",
  #     names: [NameVariant.new(full_name: "John Doe", is_primary: true)]
  #   )
  #
  class Entity < Lutaml::Model::Serializable
    # Entity types
    TYPES = %w[person organization vessel aircraft].freeze

    attribute :id, :string                        # URI identifier
    attribute :entity_type, :string               # person, organization, vessel, aircraft
    attribute :names, NameVariant, collection: true
    attribute :source_references, SourceReference, collection: true
    attribute :linked_entities, EntityLink, collection: true
    attribute :same_as, :string, collection: true # URIs of same entity in other systems
    attribute :remarks, :string

    json do
      map 'id', to: :id
      map 'entity_type', to: :entity_type
      map 'entityType', to: :entity_type # backward compatibility
      map 'names', to: :names
      map 'source_references', to: :source_references
      map 'sourceReferences', to: :source_references # backward compatibility
      map 'linked_entities', to: :linked_entities
      map 'linkedEntities', to: :linked_entities # backward compatibility
      map 'same_as', to: :same_as
      map 'sameAs', to: :same_as # backward compatibility
      map 'remarks', to: :remarks
    end

    # @return [NameVariant, nil] the primary name
    def primary_name
      names.find(&:primary?) || names.first
    end

    # @return [String, nil] the display name
    def display_name
      primary_name&.display_name
    end

    # @return [Array<String>] all name variants
    def all_names
      names.map(&:display_name).compact
    end

    # Check if this entity matches a search term
    # @param term [String] the search term
    # @return [Boolean] whether there's a match
    def matches?(term)
      term_lower = term.downcase
      all_names.any? { |name| name.downcase.include?(term_lower) }
    end

    # Get sanction entries for this entity
    # @return [Array<SanctionEntry>] sanction entries
    def sanction_entries
      @sanction_entries ||= []
    end

    # Add a sanction entry
    # @param entry [SanctionEntry] the entry to add
    def add_sanction_entry(entry)
      @sanction_entries ||= []
      @sanction_entries << entry
    end
  end
end
