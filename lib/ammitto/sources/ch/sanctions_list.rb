# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Ch
      # Alias name
      class AliasName < Lutaml::Model::Serializable
        attribute :name, :string
        attribute :type, :string

        xml do
          root 'ALIAS_NAME'
          map_element 'NAME', to: :name
          map_element 'TYPE', to: :type
        end
      end

      # Address
      class Address < Lutaml::Model::Serializable
        attribute :street, :string
        attribute :city, :string
        attribute :country, :string
        attribute :postal_code, :string

        xml do
          root 'ADDRESS'
          map_element 'STREET', to: :street
          map_element 'CITY', to: :city
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

      # Individual person in Swiss sanctions list
      class Individual < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :last_name, :string
        attribute :first_name, :string
        attribute :date_of_birth, :string
        attribute :place_of_birth, :string
        attribute :nationality, :string, collection: true
        attribute :alias_names, AliasName, collection: true
        attribute :addresses, Address, collection: true
        attribute :identifications, Identification, collection: true
        attribute :sanctions_program, :string
        attribute :list_date, :string

        xml do
          root 'INDIVIDUAL'
          map_element 'ID', to: :id
          map_element 'LAST_NAME', to: :last_name
          map_element 'FIRST_NAME', to: :first_name
          map_element 'DATE_OF_BIRTH', to: :date_of_birth
          map_element 'PLACE_OF_BIRTH', to: :place_of_birth
          map_element 'NATIONALITY', to: :nationality
          map_element 'ALIAS_NAME', to: :alias_names
          map_element 'ADDRESS', to: :addresses
          map_element 'IDENTIFICATION', to: :identifications
          map_element 'SANCTIONS_PROGRAM', to: :sanctions_program
          map_element 'LIST_DATE', to: :list_date
        end

        def full_name
          [first_name, last_name].compact.join(' ')
        end
      end

      # Entity (organization) in Swiss sanctions list
      class Entity < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :name, :string
        attribute :alias_names, AliasName, collection: true
        attribute :addresses, Address, collection: true
        attribute :sanctions_program, :string
        attribute :list_date, :string

        xml do
          root 'ENTITY'
          map_element 'ID', to: :id
          map_element 'NAME', to: :name
          map_element 'ALIAS_NAME', to: :alias_names
          map_element 'ADDRESS', to: :addresses
          map_element 'SANCTIONS_PROGRAM', to: :sanctions_program
          map_element 'LIST_DATE', to: :list_date
        end
      end

      # Swiss SECO Sanctions List (XML)
      # Source: State Secretariat for Economic Affairs (SECO)
      # URL: https://www.sesam.search.admin.ch/sesam-search-web/pages/downloadXmlGesamtliste.xhtml
      class SanctionsList < Lutaml::Model::Serializable
        attribute :individuals, Individual, collection: true
        attribute :entities, Entity, collection: true

        xml do
          root 'SECO_SANCTIONS_LIST'
          map_element 'INDIVIDUAL', to: :individuals
          map_element 'ENTITY', to: :entities
        end
      end
    end
  end
end
