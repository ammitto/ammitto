# frozen_string_literal: true

# Require dependent classes first
require_relative 'name'
require_relative 'non_latin_name'
require_relative 'address'
require_relative 'individual_details'
require_relative 'sanctions_indicators'

module Ammitto
  module Sources
    module Uk
      # Wrapper for Names collection
      class NamesWrapper < Lutaml::Model::Serializable
        attribute :items, Name, collection: true

        xml do
          root 'Names'
          map_element 'Name', to: :items
        end

        yaml do
          map 'names', to: :items
        end

        json do
          map 'names', to: :items
        end
      end

      # Wrapper for NonLatinNames collection
      class NonLatinNamesWrapper < Lutaml::Model::Serializable
        attribute :items, NonLatinName, collection: true

        xml do
          root 'NonLatinNames'
          map_element 'NonLatinName', to: :items
        end

        yaml do
          map 'names', to: :items
        end

        json do
          map 'names', to: :items
        end
      end

      # Wrapper for Addresses collection
      class AddressesWrapper < Lutaml::Model::Serializable
        attribute :items, Address, collection: true

        xml do
          root 'Addresses'
          map_element 'Address', to: :items
        end

        yaml do
          map 'addresses', to: :items
        end

        json do
          map 'addresses', to: :items
        end
      end

      # Individual sanction designation from UK OFSI
      #
      # Represents a single <Designation> element in the UK XML schema.
      # Contains all information about a sanctioned individual or entity.
      #
      # @example
      #   designation = Ammitto::Sources::Uk::Designation.from_xml(designation_xml)
      #   puts designation.unique_id
      #   puts designation.regime_name
      #   designation.names.each { |n| puts n.name6 }
      #
      class Designation < Lutaml::Model::Serializable
        attribute :last_updated, :string
        attribute :date_designated, :string
        attribute :unique_id, :string
        attribute :ofsi_group_id, :string
        attribute :un_reference_number, :string
        attribute :names_wrapper, NamesWrapper
        attribute :non_latin_names_wrapper, NonLatinNamesWrapper
        attribute :regime_name, :string
        attribute :individual_entity_ship, :string
        attribute :designation_source, :string
        attribute :sanctions_imposed, :string
        attribute :sanctions_imposed_indicators, SanctionsIndicators
        attribute :other_information, :string
        attribute :uk_statement_of_reasons, :string
        attribute :addresses_wrapper, AddressesWrapper
        attribute :individual_details, IndividualDetails

        xml do
          root 'Designation'

          map_element 'LastUpdated', to: :last_updated
          map_element 'DateDesignated', to: :date_designated
          map_element 'UniqueID', to: :unique_id
          map_element 'OFSIGroupID', to: :ofsi_group_id
          map_element 'UNReferenceNumber', to: :un_reference_number
          map_element 'Names', to: :names_wrapper
          map_element 'NonLatinNames', to: :non_latin_names_wrapper
          map_element 'RegimeName', to: :regime_name
          map_element 'IndividualEntityShip', to: :individual_entity_ship
          map_element 'DesignationSource', to: :designation_source
          map_element 'SanctionsImposed', to: :sanctions_imposed
          map_element 'SanctionsImposedIndicators', to: :sanctions_imposed_indicators
          map_element 'OtherInformation', to: :other_information
          map_element 'UKStatementofReasons', to: :uk_statement_of_reasons
          map_element 'Addresses', to: :addresses_wrapper
          map_element 'IndividualDetails', to: :individual_details
        end

        yaml do
          map 'last_updated', to: :last_updated
          map 'date_designated', to: :date_designated
          map 'unique_id', to: :unique_id
          map 'ofsi_group_id', to: :ofsi_group_id
          map 'un_reference_number', to: :un_reference_number
          map 'names', to: :names_wrapper
          map 'non_latin_names', to: :non_latin_names_wrapper
          map 'regime_name', to: :regime_name
          map 'individual_entity_ship', to: :individual_entity_ship
          map 'designation_source', to: :designation_source
          map 'sanctions_imposed', to: :sanctions_imposed
          map 'sanctions_imposed_indicators', to: :sanctions_imposed_indicators
          map 'other_information', to: :other_information
          map 'uk_statement_of_reasons', to: :uk_statement_of_reasons
          map 'addresses', to: :addresses_wrapper
          map 'individual_details', to: :individual_details
        end

        json do
          map 'last_updated', to: :last_updated
          map 'date_designated', to: :date_designated
          map 'unique_id', to: :unique_id
          map 'ofsi_group_id', to: :ofsi_group_id
          map 'un_reference_number', to: :un_reference_number
          map 'names', to: :names_wrapper
          map 'non_latin_names', to: :non_latin_names_wrapper
          map 'regime_name', to: :regime_name
          map 'individual_entity_ship', to: :individual_entity_ship
          map 'designation_source', to: :designation_source
          map 'sanctions_imposed', to: :sanctions_imposed
          map 'sanctions_imposed_indicators', to: :sanctions_imposed_indicators
          map 'other_information', to: :other_information
          map 'uk_statement_of_reasons', to: :uk_statement_of_reasons
          map 'addresses', to: :addresses_wrapper
          map 'individual_details', to: :individual_details
        end

        # Get all names (from wrapper)
        # @return [Array<Name>]
        def names
          names_wrapper&.items || []
        end

        # Get all non-latin names (from wrapper)
        # @return [Array<NonLatinName>]
        def non_latin_names
          non_latin_names_wrapper&.items || []
        end

        # Get all addresses (from wrapper)
        # @return [Array<Address>]
        def addresses
          addresses_wrapper&.items || []
        end

        # Check if this designation is for an individual
        # @return [Boolean]
        def individual?
          individual_entity_ship == 'Individual'
        end

        # Check if this designation is for an entity (organization)
        # @return [Boolean]
        def entity?
          individual_entity_ship == 'Entity'
        end

        # Get primary name
        # @return [Name, nil]
        def primary_name
          names.find(&:primary_name?)
        end

        # Get all aliases
        # @return [Array<Name>]
        def aliases
          names.reject(&:primary_name?)
        end
      end
    end
  end
end
