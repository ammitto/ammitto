# frozen_string_literal: true

require 'lutaml/model'
require_relative '../types'
require_relative '../value_objects/name_variant'
require_relative '../value_objects/source_provenance'
require_relative '../value_objects/harmonized_name'
require_relative '../value_objects/harmonized_attributes'

module Ammitto
  module Ontology
    module Entities
      # HarmonizedEntity represents a canonical, deduplicated entity
      # that may appear in multiple sanctions sources.
      #
      # This is the "golden record" that aggregates information from
      # all source-specific entities that have been matched as the
      # same real-world entity.
      #
      # Key features:
      # - Aggregates names from all sources with provenance
      # - Harmonizes entity type with conflict detection
      # - Links to all source entities via SAME_AS relationship
      # - Tracks match confidence and review status
      #
      # @example Creating a harmonized entity
      #   entity = HarmonizedEntity.new(
      #     id: "https://www.ammitto.org/entity/harmonized/aa12345",
      #     entity_type: :person,
      #     type_confidence: 0.85
      #   )
      #   entity.add_source_entity(uk_entity, confidence: 0.95)
      #   entity.add_source_entity(eu_entity, confidence: 0.92)
      #
      class HarmonizedEntity < Lutaml::Model::Serializable
        # Review status values
        REVIEW_STATUSES = %i[auto_approved pending_review reviewed disputed].freeze

        # Unique canonical IRI for this harmonized entity
        # @return [String]
        attribute :id, :string

        # Harmonized entity type (resolved from source types)
        # @return [Symbol]
        attribute :entity_type, :string

        # Confidence score for entity type (0.0-1.0)
        # Based on unanimity among source entities
        # @return [Float]
        attribute :type_confidence, :float

        # Whether there's a type conflict among sources
        # @return [Boolean]
        attribute :type_conflict, :boolean, default: false

        # Sources that disagree with the harmonized type
        # @return [Array<String>, nil]
        attribute :type_conflict_sources, :string, collection: true

        # All names from all sources, with provenance
        # @return [Array<HarmonizedName>]
        attribute :names, ValueObjects::HarmonizedName, collection: true

        # Birth information (merged from sources)
        # @return [Array<HarmonizedBirthInfo>, nil]
        attribute :birth_info, ValueObjects::HarmonizedBirthInfo, collection: true

        # Nationalities (merged from sources)
        # @return [Array<HarmonizedNationality>, nil]
        attribute :nationalities, ValueObjects::HarmonizedNationality, collection: true

        # Addresses (merged from sources)
        # @return [Array<HarmonizedAddress>, nil]
        attribute :addresses, ValueObjects::HarmonizedAddress, collection: true

        # Identifications (merged from sources)
        # @return [Array<HarmonizedIdentification>, nil]
        attribute :identifications, ValueObjects::HarmonizedIdentification, collection: true

        # References to source entities
        # @return [Array<SourceEntityReference>]
        attribute :source_entities, ValueObjects::SourceEntityReference, collection: true

        # All sanction entries from all sources
        # @return [Array]
        attr_reader :sanction_entries

        # Review status (auto_approved, pending_review, reviewed, disputed)
        # @return [Symbol]
        attribute :review_status, :string, default: 'auto_approved'

        # Notes from manual review
        # @return [String, nil]
        attribute :review_notes, :string

        def initialize(*args)
          super
          @sanction_entries ||= []
          self.review_status ||= 'auto_approved'
        end

        # Add a source entity reference
        # @param source_entity_iri [String] IRI of the source entity
        # @param source_code [String] Source code (uk, eu, un, etc.)
        # @param original_type [Symbol] Entity type from source
        # @param confidence [Float] Match confidence (0.0-1.0)
        # @return [void]
        def add_source_entity(source_entity_iri:, source_code:, original_type:, confidence:)
          source_entities << ValueObjects::SourceEntityReference.new(
            iri: source_entity_iri,
            source_code: source_code,
            original_type: original_type.to_s,
            type_matches_harmonized: original_type.to_s == entity_type.to_s,
            match_confidence: confidence
          )

          # Update type conflict status
          update_type_conflict_status
        end

        # Add a sanction entry
        # @param entry [SanctionEntry]
        # @return [void]
        def add_sanction_entry(entry)
          @sanction_entries ||= []
          @sanction_entries << entry
        end

        # Get primary name (first name marked primary, or first name)
        # @return [String, nil]
        def primary_name
          primary = names&.find(&:primary?)
          primary&.full_name || names&.first&.full_name
        end

        # Get all name variants as strings
        # @return [Array<String>]
        def all_names
          names&.map(&:full_name)&.compact || []
        end

        # Get all unique sources that mention this entity
        # @return [Array<String>]
        def sources
          source_entities&.map(&:source_code)&.uniq || []
        end

        # Check if entity needs manual review
        # @return [Boolean]
        def needs_review?
          type_conflict || type_confidence < 0.7 || review_status == 'pending_review'
        end

        # Calculate type confidence from source entities
        # @return [Float]
        def calculate_type_confidence
          return 1.0 if source_entities.empty?

          matching = source_entities.count(&:type_matches_harmonized)
          matching.to_f / source_entities.length
        end

        private

        def update_type_conflict_status
          if source_entities.any? { |se| !se.type_matches_harmonized }
            self.type_conflict = true
            self.type_conflict_sources = source_entities
                                         .reject(&:type_matches_harmonized)
                                         .map(&:source_code)
          else
            self.type_conflict = false
            self.type_conflict_sources = []
          end

          self.type_confidence = calculate_type_confidence
        end

        # JSON mapping
        json do
          map :id, to: :id
          map :entity_type, to: :entity_type
          map :type_confidence, to: :type_confidence
          map :type_conflict, to: :type_conflict
          map :type_conflict_sources, to: :type_conflict_sources
          map :names, to: :names
          map :birth_info, to: :birth_info
          map :nationalities, to: :nationalities
          map :addresses, to: :addresses
          map :identifications, to: :identifications
          map :source_entities, to: :source_entities
          map :review_status, to: :review_status
          map :review_notes, to: :review_notes
        end

        # YAML mapping
        yaml do
          map :id, to: :id
          map :entity_type, to: :entity_type
          map :type_confidence, to: :type_confidence
          map :type_conflict, to: :type_conflict
          map :type_conflict_sources, to: :type_conflict_sources
          map :names, to: :names
          map :birth_info, to: :birth_info
          map :nationalities, to: :nationalities
          map :addresses, to: :addresses
          map :identifications, to: :identifications
          map :source_entities, to: :source_entities
          map :review_status, to: :review_status
          map :review_notes, to: :review_notes
        end
      end
    end
  end
end
