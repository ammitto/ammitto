# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Ca
      # Individual record from Canadian sanctions list
      #
      # The actual XML format uses <data-set> root with <record> elements
      # containing person/entity information in a flat structure.
      #
      # Source: https://www.international.gc.ca/world-monde/assets/office_docs/
      #         international_relations-relations_internationales/sanctions/sema-lmes.xml
      #
      class Record < Lutaml::Model::Serializable
        attribute :country, :string
        attribute :last_name, :string
        attribute :given_name, :string
        attribute :date_of_birth_or_ship_build_date, :string
        attribute :schedule, :string
        attribute :item, :string
        attribute :date_of_listing, :string

        xml do
          root 'record'
          map_element 'Country', to: :country
          map_element 'LastName', to: :last_name
          map_element 'GivenName', to: :given_name
          map_element 'DateOfBirthOrShipBuildDate', to: :date_of_birth_or_ship_build_date
          map_element 'Schedule', to: :schedule
          map_element 'Item', to: :item
          map_element 'DateOfListing', to: :date_of_listing
        end

        # YAML mapping for processed YAML files
        yaml do
          map 'country', to: :country
          map 'last_name', to: :last_name
          map 'given_name', to: :given_name
          map 'date_of_birth_or_ship_build_date', to: :date_of_birth_or_ship_build_date
          map 'schedule', to: :schedule
          map 'item', to: :item
          map 'date_of_listing', to: :date_of_listing
        end

        # Get full name
        # @return [String]
        def full_name
          [given_name, last_name].compact.join(' ')
        end

        # Check if this is an individual (has personal name)
        # @return [Boolean]
        def individual?
          !last_name.to_s.strip.empty? || !given_name.to_s.strip.empty?
        end

        # Get entity type based on content
        # @return [String] 'person' or 'organization'
        def entity_type
          # If has LastName/GivenName, it's a person
          if last_name || given_name
            'person'
          else
            'organization'
          end
        end

        # Generate a unique ID
        # @return [String]
        def generate_id
          parts = [country, schedule, item].compact
          parts.join('-').gsub(/[^a-zA-Z0-9-]/, '-').gsub(/-+/, '-')
        end

        # Convert to hash for YAML serialization
        # @return [Hash]
        def to_hash
          hash = {
            id: generate_id,
            entity_type: entity_type,
            country: country,
            schedule: schedule,
            item: item,
            date_of_listing: date_of_listing
          }
          hash[:names] = [{ full_name: full_name, is_primary: true }] if full_name && !full_name.empty?
          hash[:date_of_birth] = date_of_birth_or_ship_build_date if date_of_birth_or_ship_build_date
          hash.compact
        end
      end

      # Canadian Consolidated Autonomous Sanctions List (XML)
      #
      # The actual XML format uses <data-set> as root element with <record>
      # children. Each record represents either an individual or entity.
      #
      # @example Parsing from XML
      #   list = Ca::SanctionsList.from_xml(xml_content)
      #   list.records.each do |record|
      #     puts record.full_name
      #   end
      #
      class SanctionsList < Lutaml::Model::Serializable
        attribute :records, Record, collection: true

        xml do
          root 'data-set'
          map_element 'record', to: :records
        end

        # Get all individuals (records with names)
        # @return [Array<Record>]
        def individuals
          records.select(&:individual?)
        end

        # Get all entities (records without personal names)
        # @return [Array<Record>]
        def entities
          records.reject(&:individual?)
        end
      end
    end
  end
end
