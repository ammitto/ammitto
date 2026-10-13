# frozen_string_literal: true

require 'lutaml/model'
require_relative 'individual'

module Ammitto
  module Sources
    module Uk
      # The <IndividualDetails> element of a UK designation.
      #
      # OFSI nests the person-level facts one level down, in a single
      # <Individual>; the readers below pass through to it so callers keep
      # asking the details object for dobs, nationalities and the rest.
      #
      # @example
      #   details = Ammitto::Sources::Uk::IndividualDetails.from_xml(xml)
      #   details.dobs.each { |d| puts d }
      #   details.nationalities.each { |n| puts n }
      #
      class IndividualDetails < Lutaml::Model::Serializable
        attribute :individual, Individual

        xml do
          root 'IndividualDetails'
          map_element 'Individual', to: :individual
        end

        key_value do
          map 'individual', to: :individual
        end

        # @return [Array<String>] dates of birth, normalized
        def dobs
          individual&.dobs || []
        end

        # @return [Array<String>]
        def nationalities
          individual&.nationalities || []
        end

        # @return [Array<String>]
        def positions
          individual&.positions || []
        end

        # @return [Array<String>]
        def genders
          individual&.genders || []
        end

        # @return [BirthDetails, nil]
        def birth_details
          individual&.birth_details
        end

        # @return [Array<Passport>]
        def passports
          individual&.passports || []
        end

        # @return [Array<NationalIdentifier>]
        def national_identifiers
          individual&.national_identifiers || []
        end

        # Get primary date of birth (first non-placeholder)
        # @return [String, nil]
        def primary_dob
          dobs.find { |d| !d.include?('dd/mm') && !d.include?('--') }
        end

        # Check if there are valid (non-placeholder) DOBs
        # @return [Boolean]
        def valid_dobs?
          dobs.any? { |d| !d.include?('dd/mm') && !d.include?('--') }
        end
      end
    end
  end
end
