# frozen_string_literal: true

require 'lutaml/model'
require_relative 'date_normalizer'
require_relative 'birth_details'
require_relative 'xml_text_list'
require_relative 'passport_details'
require_relative 'national_identifier_details'

module Ammitto
  module Sources
    module Uk
      # The <Individual> block inside <IndividualDetails>: the person-level
      # facts OFSI publishes (dates of birth, nationalities, positions,
      # birth places, gender and identity documents).
      class Individual < Lutaml::Model::Serializable
        extend XmlTextList
        include DateNormalizer

        attribute :dobs, :string, collection: true
        attribute :nationalities, :string, collection: true
        attribute :positions, :string, collection: true
        attribute :genders, :string, collection: true
        attribute :birth_details, BirthDetails
        attribute :passport_details, PassportDetails
        attribute :national_identifier_details, NationalIdentifierDetails

        text_list :dobs, 'DOB'
        text_list :nationalities, 'Nationality'
        text_list :positions, 'Position'
        text_list :genders, 'Gender'

        xml do
          root 'Individual'

          map_element 'DOBs', to: :dobs,
                              **XmlTextList.handlers(:dobs)
          map_element 'Nationalities', to: :nationalities,
                                       **XmlTextList.handlers(:nationalities)
          map_element 'Positions', to: :positions,
                                   **XmlTextList.handlers(:positions)
          map_element 'Genders', to: :genders,
                                 **XmlTextList.handlers(:genders)
          map_element 'BirthDetails', to: :birth_details
          map_element 'PassportDetails', to: :passport_details
          map_element 'NationalIdentifierDetails',
                      to: :national_identifier_details
        end

        key_value do
          map 'dobs', to: :dobs
          map 'nationalities', to: :nationalities
          map 'positions', to: :positions
          map 'genders', to: :genders
          map 'birth_details', to: :birth_details
          map 'passport_details', to: :passport_details
          map 'national_identifier_details', to: :national_identifier_details
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

        # @return [Array<Passport>]
        def passports
          passport_details&.items || []
        end

        # @return [Array<NationalIdentifier>]
        def national_identifiers
          national_identifier_details&.items || []
        end
      end
    end
  end
end
