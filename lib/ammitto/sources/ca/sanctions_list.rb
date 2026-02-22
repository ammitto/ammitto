# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Ca
      # Date of birth
      class DateOfBirth < Lutaml::Model::Serializable
        attribute :date, :string
        attribute :type, :string

        xml do
          root 'DATE_OF_BIRTH'
          map_element 'DATE', to: :date
          map_element 'TYPE', to: :type
        end
      end

      # Place of birth
      class PlaceOfBirth < Lutaml::Model::Serializable
        attribute :city, :string
        attribute :province, :string
        attribute :country, :string

        xml do
          root 'PLACE_OF_BIRTH'
          map_element 'CITY', to: :city
          map_element 'PROVINCE', to: :province
          map_element 'COUNTRY', to: :country
        end
      end

      # Alias name
      class Alias < Lutaml::Model::Serializable
        attribute :name, :string
        attribute :type, :string

        xml do
          root 'ALIAS'
          map_element 'NAME', to: :name
          map_element 'TYPE', to: :type
        end
      end

      # Address
      class Address < Lutaml::Model::Serializable
        attribute :street, :string
        attribute :city, :string
        attribute :province, :string
        attribute :country, :string
        attribute :postal_code, :string

        xml do
          root 'ADDRESS'
          map_element 'STREET', to: :street
          map_element 'CITY', to: :city
          map_element 'PROVINCE', to: :province
          map_element 'COUNTRY', to: :country
          map_element 'POSTAL_CODE', to: :postal_code
        end
      end

      # Identification document
      class Identification < Lutaml::Model::Serializable
        attribute :type, :string
        attribute :number, :string
        attribute :country, :string

        xml do
          root 'IDENTIFICATION'
          map_element 'TYPE', to: :type
          map_element 'NUMBER', to: :number
          map_element 'COUNTRY', to: :country
        end
      end

      # Individual person in Canadian sanctions list
      class Individual < Lutaml::Model::Serializable
        attribute :id, :integer
        attribute :first_name, :string
        attribute :last_name, :string
        attribute :date_of_birth, DateOfBirth, collection: true
        attribute :place_of_birth, PlaceOfBirth, collection: true
        attribute :nationality, :string, collection: true
        attribute :aliases, Alias, collection: true
        attribute :addresses, Address, collection: true
        attribute :identifications, Identification, collection: true
        attribute :sanctions_program, :string
        attribute :schedule, :string

        xml do
          root 'INDIVIDUAL'
          map_element 'ID', to: :id
          map_element 'FIRST_NAME', to: :first_name
          map_element 'LAST_NAME', to: :last_name
          map_element 'DATE_OF_BIRTH', to: :date_of_birth
          map_element 'PLACE_OF_BIRTH', to: :place_of_birth
          map_element 'NATIONALITY', to: :nationality
          map_element 'ALIAS', to: :aliases
          map_element 'ADDRESS', to: :addresses
          map_element 'IDENTIFICATION', to: :identifications
          map_element 'SANCTIONS_PROGRAM', to: :sanctions_program
          map_element 'SCHEDULE', to: :schedule
        end

        def full_name
          [first_name, last_name].compact.join(' ')
        end
      end

      # Entity (organization) in Canadian sanctions list
      class Entity < Lutaml::Model::Serializable
        attribute :id, :integer
        attribute :name, :string
        attribute :aliases, Alias, collection: true
        attribute :addresses, Address, collection: true
        attribute :sanctions_program, :string
        attribute :schedule, :string

        xml do
          root 'ENTITY'
          map_element 'ID', to: :id
          map_element 'NAME', to: :name
          map_element 'ALIAS', to: :aliases
          map_element 'ADDRESS', to: :addresses
          map_element 'SANCTIONS_PROGRAM', to: :sanctions_program
          map_element 'SCHEDULE', to: :schedule
        end
      end

      # Wrapper for Individuals collection
      class IndividualsWrapper < Lutaml::Model::Serializable
        attribute :items, Individual, collection: true

        xml do
          root 'INDIVIDUALS'
          map_element 'INDIVIDUAL', to: :items
        end
      end

      # Wrapper for Entities collection
      class EntitiesWrapper < Lutaml::Model::Serializable
        attribute :items, Entity, collection: true

        xml do
          root 'ENTITIES'
          map_element 'ENTITY', to: :items
        end
      end

      # Canadian Consolidated Autonomous Sanctions List (XML)
      # Source: Global Affairs Canada
      # URL: https://www.international.gc.ca/world-monde/assets/office_docs/international_relations-relations_internationales/sanctions/sema-lmes.xml
      class SanctionsList < Lutaml::Model::Serializable
        attribute :individuals_wrapper, IndividualsWrapper
        attribute :entities_wrapper, EntitiesWrapper

        xml do
          root 'CONSOLIDATED_LIST'
          map_element 'INDIVIDUALS', to: :individuals_wrapper
          map_element 'ENTITIES', to: :entities_wrapper
        end

        # Get all individuals
        def individuals
          individuals_wrapper&.items || []
        end

        # Get all entities
        def entities
          entities_wrapper&.items || []
        end
      end
    end
  end
end
