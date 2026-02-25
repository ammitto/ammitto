# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Ch
      # Name part in Swiss sanctions list (given-name, family-name, etc.)
      class NamePart < Lutaml::Model::Serializable
        attribute :order, :integer
        attribute :name_part_type, :string
        attribute :value, :string

        xml do
          root 'name-part'
          map_attribute 'order', to: :order
          map_attribute 'name-part-type', to: :name_part_type
          map_element 'value', to: :value
        end

        yaml do
          map 'order', to: :order
          map 'name_part_type', to: :name_part_type
          map 'value', to: :value
        end
      end

      # Name in Swiss sanctions list
      class Name < Lutaml::Model::Serializable
        attribute :name_type, :string
        attribute :quality, :string
        attribute :lang, :string
        attribute :name_parts, NamePart, collection: true

        xml do
          root 'name'
          map_attribute 'name-type', to: :name_type
          map_attribute 'quality', to: :quality
          map_attribute 'lang', to: :lang
          map_element 'name-part', to: :name_parts
        end

        yaml do
          map 'name_type', to: :name_type
          map 'quality', to: :quality
          map 'lang', to: :lang
          map 'name_parts', to: :name_parts
        end

        # Get full name from name parts
        def full_name
          name_parts.sort_by(&:order).map(&:value).compact.join(' ')
        end
      end

      # Date of birth in Swiss sanctions list
      class DayMonthYear < Lutaml::Model::Serializable
        attribute :day, :integer
        attribute :month, :integer
        attribute :year, :integer

        xml do
          root 'day-month-year'
          map_attribute 'day', to: :day
          map_attribute 'month', to: :month
          map_attribute 'year', to: :year
        end

        yaml do
          map 'day', to: :day
          map 'month', to: :month
          map 'year', to: :year
        end

        def to_iso_date
          return nil unless year

          "#{year}-#{month.to_s.rjust(2, '0')}-#{day.to_s.rjust(2, '0')}"
        end
      end

      # Address in Swiss sanctions list
      class Address < Lutaml::Model::Serializable
        attribute :address_details, :string
        attribute :zip_code, :string

        xml do
          root 'address'
          map_element 'address-details', to: :address_details
          map_element 'zip-code', to: :zip_code
        end

        yaml do
          map 'address_details', to: :address_details
          map 'zip_code', to: :zip_code
        end
      end

      # Identity (person or entity) in Swiss sanctions list
      class Identity < Lutaml::Model::Serializable
        attribute :ssid, :string
        attribute :main, :string
        attribute :names, Name, collection: true
        attribute :day_month_year, DayMonthYear
        attribute :addresses, Address, collection: true

        xml do
          root 'identity'
          map_attribute 'ssid', to: :ssid
          map_attribute 'main', to: :main
          map_element 'name', to: :names
          map_element 'day-month-year', to: :day_month_year
          map_element 'address', to: :addresses
        end

        yaml do
          map 'ssid', to: :ssid
          map 'main', to: :main
          map 'names', to: :names
          map 'day_month_year', to: :day_month_year
          map 'addresses', to: :addresses
        end

        def full_name
          names.first&.full_name
        end

        def person?
          names.any? { |n| n.name_parts.any? { |p| p.name_part_type == 'given-name' } }
        end

        def entity_type
          person? ? 'person' : 'organization'
        end
      end

      # Individual in Swiss sanctions list
      class Individual < Lutaml::Model::Serializable
        attribute :identity, Identity
        attribute :justification, :string

        xml do
          root 'individual'
          map_element 'identity', to: :identity
          map_element 'justification', to: :justification
        end

        yaml do
          map 'identity', to: :identity
          map 'justification', to: :justification
        end
      end

      # Entity (organization) in Swiss sanctions list
      class Entity < Lutaml::Model::Serializable
        attribute :identity, Identity
        attribute :justification, :string

        xml do
          root 'entity'
          map_element 'identity', to: :identity
          map_element 'justification', to: :justification
        end

        yaml do
          map 'identity', to: :identity
          map 'justification', to: :justification
        end
      end

      # Target in Swiss sanctions list (contains individual or entity)
      class Target < Lutaml::Model::Serializable
        attribute :ssid, :string
        attribute :sanctions_set_id, :string
        attribute :individual, Individual
        attribute :entity, Entity

        xml do
          root 'target'
          map_attribute 'ssid', to: :ssid
          map_element 'sanctions-set-id', to: :sanctions_set_id
          map_element 'individual', to: :individual
          map_element 'entity', to: :entity
        end

        yaml do
          map 'ssid', to: :ssid
          map 'sanctions_set_id', to: :sanctions_set_id
          map 'individual', to: :individual
          map 'entity', to: :entity
        end

        def identity
          individual&.identity || entity&.identity
        end

        def full_name
          identity&.full_name
        end

        def entity_type
          individual ? 'person' : 'organization'
        end
      end

      # Sanctions program in Swiss sanctions list
      class SanctionsProgram < Lutaml::Model::Serializable
        attribute :ssid, :string
        attribute :program_keys, :string, collection: true

        xml do
          root 'sanctions-program'
          map_attribute 'ssid', to: :ssid
          map_element 'program-key', to: :program_keys
        end

        yaml do
          map 'ssid', to: :ssid
          map 'program_keys', to: :program_keys
        end
      end

      # Swiss SECO Sanctions List (XML)
      #
      # The XML has two main sections:
      # - sanctions-program: regime information
      # - target: sanctioned individuals and entities
      #
      class SanctionsList < Lutaml::Model::Serializable
        attribute :list_type, :string
        attribute :date, :string
        attribute :programs, SanctionsProgram, collection: true
        attribute :targets, Target, collection: true

        xml do
          root 'swiss-sanctions-list'
          map_attribute 'list-type', to: :list_type
          map_attribute 'date', to: :date
          map_element 'sanctions-program', to: :programs
          map_element 'target', to: :targets
        end

        yaml do
          map 'list_type', to: :list_type
          map 'date', to: :date
          map 'programs', to: :programs
          map 'targets', to: :targets
        end

        # Get all identities for YAML output
        # @return [Array<Target>]
        def all_identities
          targets
        end

        # Get all individuals
        # @return [Array<Target>]
        def individuals
          targets.select { |t| t.individual }
        end

        # Get all entities (organizations)
        # @return [Array<Target>]
        def entities
          targets.select { |t| t.entity }
        end
      end
    end
  end
end
