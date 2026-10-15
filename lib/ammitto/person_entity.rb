# frozen_string_literal: true

require_relative 'entity'
require_relative 'address'
require_relative 'birth_info'
require_relative 'contact_info'
require_relative 'identification'
require_relative 'utils/presence'
require_relative 'ontology/contracts'
require_relative 'ontology/entities/person_entity'

module Ammitto
  # PersonEntity represents a sanctioned individual person
  #
  # Legacy facade: its fields are projected from
  # Ontology::Entities::PersonEntity (see Ontology::Contracts).
  #
  # @example Creating a person entity
  #   PersonEntity.new(
  #     id: "https://ammitto.org/entity/123",
  #     names: [NameVariant.new(full_name: "Ri Won Ho", is_primary: true)],
  #     birth_info: [BirthInfo.new(date: "1964-07-17", country: "DPRK")],
  #     nationalities: ["Democratic People's Republic of Korea"]
  #   )
  #
  class PersonEntity < Entity
    Ontology::Contracts.declare_legacy_attributes(self)

    json do
      map 'entityType', to: :entity_type
      map 'birthInfo', to: :birth_info
      map 'deathDate', to: :death_date
      map 'nationalities', to: :nationalities
      map 'gender', to: :gender
      map 'identifications', to: :identifications
      map 'addresses', to: :addresses
      map 'contactInfo', to: :contact_info
      map 'title', to: :title
      map 'position', to: :position
      map 'affiliation', to: :affiliation
    end

    # @return [Boolean] whether the person is deceased
    def deceased?
      !death_date.nil?
    end

    # @return [BirthInfo, nil] primary birth info
    def primary_birth_info
      birth_info.first
    end

    # @return [String, nil] formatted birth date
    def birth_date
      primary_birth_info&.date
    end

    # @return [String, nil] birth country
    def birth_country
      birth_info&.find { |birth| Utils::Presence.present?(birth&.country) }&.country
    end

    # Check if this person matches a search term
    # @param term [String] the search term
    # @return [Boolean] whether there's a match
    def matches?(term)
      return true if super

      term_lower = term.downcase

      # Check nationalities
      return true if nationalities&.any? { |n| n.downcase.include?(term_lower) }

      # Check identifications
      return true if identifications&.any? do |id|
        id.number&.downcase&.include?(term_lower) ||
        id.to_s.downcase&.include?(term_lower)
      end

      false
    end
  end
end
