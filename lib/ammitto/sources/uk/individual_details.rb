# frozen_string_literal: true

require_relative 'date_normalizer'

module Ammitto
  module Sources
    module Uk
      # Birth location (town and country)
      #
      class Location < Lutaml::Model::Serializable
        attribute :town_of_birth, :string
        attribute :country_of_birth, :string

        xml do
          root 'Location'
          map_element 'TownOfBirth', to: :town_of_birth
          map_element 'CountryOfBirth', to: :country_of_birth
        end

        yaml do
          map 'town_of_birth', to: :town_of_birth
          map 'country_of_birth', to: :country_of_birth
        end

        # Format as string
        # @return [String]
        def to_s
          [town_of_birth, country_of_birth].compact.join(', ')
        end
      end

      # Birth details with location information
      #
      # Contains place of birth information (town and country).
      # May have multiple locations.
      #
      class BirthDetails < Lutaml::Model::Serializable
        attribute :locations, Location, collection: true

        xml do
          root 'BirthDetails'
          map_element 'Location', to: :locations
        end

        yaml do
          map 'locations', to: :locations
        end

        # Get primary birth location
        # @return [Location, nil]
        def primary_location
          locations.first
        end
      end

      # Individual-specific details for UK designation
      #
      # Contains person-specific information like DOB, nationalities,
      # positions, and birth details.
      #
      # @example
      #   details = Ammitto::Sources::Uk::IndividualDetails.from_xml(xml)
      #   details.dobs.each { |d| puts d }
      #   details.nationalities.each { |n| puts n }
      #
      class IndividualDetails < Lutaml::Model::Serializable
        include DateNormalizer

        attribute :dobs, :string, collection: true
        attribute :nationalities, :string, collection: true
        attribute :positions, :string, collection: true
        attribute :birth_details, BirthDetails

        xml do
          root 'IndividualDetails'

          # NOTE: Lutaml::Model handles nested collections with wrapper elements
          map_element 'DOBs', to: :dobs do
            map_element 'DOB', to: :dobs
          end
          map_element 'Nationalities', to: :nationalities do
            map_element 'Nationality', to: :nationalities
          end
          map_element 'Positions', to: :positions do
            map_element 'Position', to: :positions
          end
          map_element 'BirthDetails', to: :birth_details
        end

        yaml do
          map 'dobs', to: :dobs
          map 'nationalities', to: :nationalities
          map 'positions', to: :positions
          map 'birth_details', to: :birth_details
        end

        # Get primary date of birth (first non-placeholder)
        # @return [String, nil]
        def primary_dob
          normalized_dobs.find { |d| !d.include?('dd/mm') && !d.include?('--') }
        end

        # Check if there are valid (non-placeholder) DOBs
        # @return [Boolean]
        def valid_dobs?
          normalized_dobs.any? { |d| !d.include?('dd/mm') && !d.include?('--') }
        end

        # Get all DOBs in normalized ISO format
        # @return [Array<String>]
        def normalized_dobs
          return [] if @dobs.nil?

          @dobs.map { |d| normalize_date(d) }
        end

        # Override to return normalized DOBs
        # @return [Array<String>]
        def dobs
          normalized_dobs
        end
      end
    end
  end
end
