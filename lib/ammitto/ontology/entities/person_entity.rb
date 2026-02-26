# frozen_string_literal: true

require_relative 'entity'

module Ammitto
  module Ontology
    module Entities
      # Represents a person (individual) subject to sanctions
      #
      # PersonEntity extends Entity with person-specific attributes
      # such as birth information, gender, and nationalities.
      #
      # @example Creating a person entity
      #   person = PersonEntity.new(
      #     id: "https://www.ammitto.org/entity/eu/EU.123.45",
      #     names: [
      #       NameVariant.new(full_name: "Ivan Ivanov", is_primary: true),
      #       NameVariant.new(full_name: "Иван Иванов", script: "Cyrl")
      #     ],
      #     birth_info: [BirthInfo.new(date: Date.new(1970, 1, 1), city: "Moscow")],
      #     gender: :male,
      #     nationalities: ["RU"]
      #   )
      #
      class PersonEntity < Entity
        # Name variants for this person
        # @return [Array<NameVariant>]
        attribute :names, ValueObjects::NameVariant, collection: true

        # Birth information (may have multiple entries for uncertainty)
        # @return [Array<BirthInfo>]
        attribute :birth_info, ValueObjects::BirthInfo, collection: true

        # Date of death (if deceased)
        # @return [Date, nil]
        attribute :death_date, :date

        # Nationalities (ISO 3166-1 alpha-2 codes)
        # @return [Array<String>, nil]
        attribute :nationalities, :string, collection: true

        # Gender
        # @return [Symbol, String, nil]
        attribute :gender, :string

        # Identification documents
        # @return [Array<Identification>, nil]
        attribute :identifications, ValueObjects::Identification, collection: true

        # Addresses
        # @return [Array<Address>, nil]
        attribute :addresses, ValueObjects::Address, collection: true

        # Contact information
        # @return [ContactInfo, nil]
        attribute :contact_info, ValueObjects::ContactInfo

        # Title (Mr, Mrs, Dr, etc.)
        # @return [String, nil]
        attribute :title, :string

        # Position/role
        # @return [String, nil]
        attribute :position, :string

        # Affiliation (organization person is associated with)
        # @return [String, nil]
        attribute :affiliation, :string

        def initialize(*args)
          super
          self.entity_type = 'person'
        end

        # Get primary name
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

        # Get primary birth date
        # @return [Date, nil]
        def birth_date
          birth_info&.first&.date
        end

        # Get primary birth year
        # @return [Integer, nil]
        def birth_year
          birth_info&.first&.birth_year
        end

        # Get place of birth
        # @return [String, nil]
        def place_of_birth
          bi = birth_info&.first
          return nil unless bi

          [bi.city, bi.country].compact.join(', ')
        end

        # Get gender as normalized symbol
        # @return [Symbol, nil]
        def gender_sym
          Types.normalize_gender(gender)
        end

        # Convert to hash for JSON-LD serialization
        # @return [Hash]
        def to_hash
          hash = super
          hash[:names] = names.map(&:to_hash) if names&.any?
          hash[:birth_info] = birth_info.map(&:to_hash) if birth_info&.any?
          hash[:death_date] = death_date.to_s if death_date
          hash[:nationalities] = nationalities if nationalities&.any?
          hash[:gender] = gender if gender
          hash[:identifications] = identifications.map(&:to_hash) if identifications&.any?
          hash[:addresses] = addresses.map(&:to_hash) if addresses&.any?
          hash[:contact_info] = contact_info.to_hash if contact_info&.present?
          hash[:title] = title if title
          hash[:position] = position if position
          hash[:affiliation] = affiliation if affiliation
          hash
        end

        # JSON mapping
        json do
          map :id, to: :id
          map :entity_type, to: :entity_type
          map :names, to: :names
          map :birth_info, to: :birth_info
          map :death_date, to: :death_date
          map :nationalities, to: :nationalities
          map :gender, to: :gender
          map :identifications, to: :identifications
          map :addresses, to: :addresses
          map :contact_info, to: :contact_info
          map :title, to: :title
          map :position, to: :position
          map :affiliation, to: :affiliation
          map :source_references, to: :source_references
          map :same_as, to: :same_as
          map :remarks, to: :remarks
        end

        # YAML mapping
        yaml do
          map :id, to: :id
          map :entity_type, to: :entity_type
          map :names, to: :names
          map :birth_info, to: :birth_info
          map :death_date, to: :death_date
          map :nationalities, to: :nationalities
          map :gender, to: :gender
          map :identifications, to: :identifications
          map :addresses, to: :addresses
          map :contact_info, to: :contact_info
          map :title, to: :title
          map :position, to: :position
          map :affiliation, to: :affiliation
          map :source_references, to: :source_references
          map :same_as, to: :same_as
          map :remarks, to: :remarks
        end
      end
    end
  end
end
