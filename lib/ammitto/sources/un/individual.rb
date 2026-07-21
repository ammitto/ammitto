# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Un
      # Individual person from UN sanctions list
      #
      # Example XML:
      # <INDIVIDUAL>
      #   <DATAID>6907993</DATAID>
      #   <FIRST_NAME>ERIC</FIRST_NAME>
      #   <SECOND_NAME>BADEGE</SECOND_NAME>
      #   <UN_LIST_TYPE>DRC</UN_LIST_TYPE>
      #   <REFERENCE_NUMBER>CDi.001</REFERENCE_NUMBER>
      #   <LISTED_ON>2012-12-31</LISTED_ON>
      #   <GENDER>Male</GENDER>
      #   <COMMENTS1>...</COMMENTS1>
      #   <NATIONALITY><VALUE>...</VALUE></NATIONALITY>
      #   <DESIGNATION><VALUE>...</VALUE></DESIGNATION>
      #   <INDIVIDUAL_ALIAS>...</INDIVIDUAL_ALIAS>
      #   <INDIVIDUAL_ADDRESS>...</INDIVIDUAL_ADDRESS>
      #   <INDIVIDUAL_DATE_OF_BIRTH>...</INDIVIDUAL_DATE_OF_BIRTH>
      #   <INDIVIDUAL_PLACE_OF_BIRTH>...</INDIVIDUAL_PLACE_OF_BIRTH>
      #   <INDIVIDUAL_DOCUMENT>...</INDIVIDUAL_DOCUMENT>
      # </INDIVIDUAL>
      class Individual < Lutaml::Model::Serializable
        attribute :dataid, :string
        attribute :versionnum, :string
        attribute :first_name, :string
        attribute :second_name, :string
        attribute :third_name, :string
        attribute :fourth_name, :string
        attribute :un_list_type, :string
        attribute :reference_number, :string
        attribute :listed_on, :string
        attribute :gender, :string
        attribute :comments1, :string
        attribute :nationalities, Nationality, collection: true
        attribute :designations, Designation, collection: true
        attribute :list_type, ValueWrapper
        attribute :last_day_updated, ValueWrapper
        attribute :aliases, IndividualAlias, collection: true
        attribute :addresses, IndividualAddress, collection: true
        attribute :date_of_birth, IndividualDateOfBirth
        attribute :place_of_birth, IndividualPlaceOfBirth
        attribute :documents, IndividualDocument, collection: true
        attribute :sort_key, :string
        attribute :sort_key_last_mod, :string

        xml do
          root 'INDIVIDUAL'
          map_element 'DATAID', to: :dataid
          map_element 'VERSIONNUM', to: :versionnum
          map_element 'FIRST_NAME', to: :first_name
          map_element 'SECOND_NAME', to: :second_name
          map_element 'THIRD_NAME', to: :third_name
          map_element 'FOURTH_NAME', to: :fourth_name
          map_element 'UN_LIST_TYPE', to: :un_list_type
          map_element 'REFERENCE_NUMBER', to: :reference_number
          map_element 'LISTED_ON', to: :listed_on
          map_element 'GENDER', to: :gender
          map_element 'COMMENTS1', to: :comments1
          map_element 'NATIONALITY', to: :nationalities
          map_element 'DESIGNATION', to: :designations
          map_element 'LIST_TYPE', to: :list_type
          map_element 'LAST_DAY_UPDATED', to: :last_day_updated
          map_element 'INDIVIDUAL_ALIAS', to: :aliases
          map_element 'INDIVIDUAL_ADDRESS', to: :addresses
          map_element 'INDIVIDUAL_DATE_OF_BIRTH', to: :date_of_birth
          map_element 'INDIVIDUAL_PLACE_OF_BIRTH', to: :place_of_birth
          map_element 'INDIVIDUAL_DOCUMENT', to: :documents
          map_element 'SORT_KEY', to: :sort_key
          map_element 'SORT_KEY_LAST_MOD', to: :sort_key_last_mod
        end

        yaml do
          map 'dataid', to: :dataid
          map 'versionnum', to: :versionnum
          map 'first_name', to: :first_name
          map 'second_name', to: :second_name
          map 'third_name', to: :third_name
          map 'fourth_name', to: :fourth_name
          map 'un_list_type', to: :un_list_type
          map 'reference_number', to: :reference_number
          map 'listed_on', to: :listed_on
          map 'gender', to: :gender
          map 'comments1', to: :comments1
          map 'nationalities', to: :nationalities
          map 'designations', to: :designations
          map 'list_type', to: :list_type
          map 'last_day_updated', to: :last_day_updated
          map 'aliases', to: :aliases
          map 'addresses', to: :addresses
          map 'date_of_birth', to: :date_of_birth
          map 'place_of_birth', to: :place_of_birth
          map 'documents', to: :documents
          map 'sort_key', to: :sort_key
          map 'sort_key_last_mod', to: :sort_key_last_mod
        end

        # Helper methods
        def full_name
          [first_name, second_name, third_name, fourth_name].compact.join(' ')
        end

        def primary_name
          full_name
        end

        def nationality_values
          nationalities&.map(&:value)&.compact || []
        end

        def designation_values
          designations&.flat_map(&:values)&.compact || []
        end
      end
    end
  end
end
