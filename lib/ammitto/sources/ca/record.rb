# frozen_string_literal: true

require 'lutaml/model'
require_relative '../../utils/presence'

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
        # <EntityOrShip-EntiteOuNavire> carries the only name an
        # organization or vessel record has. Well over a third of
        # sema-lmes.xml has no personal-name element at all, so leaving
        # this one unmapped publishes those records as nameless nodes.
        attribute :entity_or_ship, :string
        attribute :entity_type, :string # Serialized for proper entity type detection
        attribute :date_of_birth_or_ship_build_date, :string
        attribute :schedule, :string
        attribute :item, :string
        attribute :date_of_listing, :string
        # <Aliases-Alias> holds every alias in one string, mostly
        # separated by semicolons. Kept as the source wrote it so the
        # processed YAML round-trips; #alias_names splits it.
        attribute :aliases, :string
        # <ShipIMONumber-NumeroOMIDuNavire> is not always an IMO number:
        # the 2026-09-22 Iran additions (items 116 to 120) carry a Persian
        # personal name in it. Kept as written; #imo_number is the
        # guarded reading.
        attribute :ship_imo_number, :string
        # A person's title or rank for personal records, a vessel type for
        # ships, in the bilingual "English | French" form.
        attribute :title_or_ship_type, :string

        # Canada renamed every element to a bilingual form between the
        # 24 and 25 August 2026 harvests: <Country> became <Country-Pays>,
        # <LastName> became <LastName-NomDeFamille>, and so on. The root
        # and <record> names did not change, so the document still parsed
        # into 5690 Records — every one of them with every field nil.
        # Names below are transcribed from the live file, fetched
        # 2026-08-27: 2,881,628 bytes, 5690 <record> elements.
        xml do
          root 'record'
          map_element 'Country-Pays', to: :country
          map_element 'LastName-NomDeFamille', to: :last_name
          map_element 'GivenName-Prenom', to: :given_name
          map_element 'EntityOrShip-EntiteOuNavire', to: :entity_or_ship
          map_element 'DateOfBirthOrShipBuildDate-' \
                      'DateDeNaissanceOuDateDeConstructionDuNavire',
                      to: :date_of_birth_or_ship_build_date
          map_element 'Schedule-Annexe', to: :schedule
          map_element 'Item-NumeroDarticle', to: :item
          map_element 'DateOfListing-DateDinscription', to: :date_of_listing
          map_element 'Aliases-Alias', to: :aliases
          map_element 'ShipIMONumber-NumeroOMIDuNavire', to: :ship_imo_number
          map_element 'TitleOrShipType-TitreOuTypeDeNavire',
                      to: :title_or_ship_type
        end

        # YAML mapping for processed YAML files
        yaml do
          map 'country', to: :country
          map 'last_name', to: :last_name
          map 'given_name', to: :given_name
          map 'entity_or_ship', to: :entity_or_ship
          map 'entity_type', to: :entity_type
          map 'date_of_birth_or_ship_build_date', to: :date_of_birth_or_ship_build_date
          map 'schedule', to: :schedule
          map 'item', to: :item
          map 'date_of_listing', to: :date_of_listing
          map 'aliases', to: :aliases
          map 'ship_imo_number', to: :ship_imo_number
          map 'title_or_ship_type', to: :title_or_ship_type
        end

        IMO_NUMBER = /\A\d{7}\z/

        # The IMO number, only when the element holds one.
        # @return [String, nil]
        def imo_number
          value = ship_imo_number.to_s.strip
          value if IMO_NUMBER.match?(value)
        end

        # Whether this record is a vessel: the only records that carry a
        # genuine IMO number.
        # @return [Boolean]
        def vessel?
          !imo_number.nil?
        end

        # Each alias in <Aliases-Alias>. The list is split on semicolons
        # only: a free-text " or " joins variants in some entries but also
        # sits inside single names, and guessing which would invent
        # structure the source does not state.
        # @return [Array<String>]
        def alias_names
          aliases.to_s.split(';').map { |part| squish(part) }.reject(&:empty?).uniq
        end

        # The title or ship type in the English half of the bilingual
        # value; the full text stays in #title_or_ship_type.
        # @return [String, nil]
        def english_title_or_ship_type
          value = squish(title_or_ship_type.to_s.split('|', 2).first)
          value unless value.empty?
        end

        # Source values carry line breaks and non-breaking spaces inside
        # and around names and types.
        def squish(text)
          text.to_s.gsub(/[[:space:]]+/, ' ').strip
        end
        private :squish

        # Get full name. Person records carry GivenName/LastName;
        # organization and ship records carry EntityOrShip instead.
        # @return [String]
        def full_name
          person = [given_name, last_name].compact.join(' ')
          return person unless person.strip.empty?

          entity_or_ship.to_s
        end

        # Check if this is an individual (has personal name)
        # @return [Boolean]
        def individual?
          !last_name.to_s.strip.empty? || !given_name.to_s.strip.empty?
        end

        # Get entity type based on content
        # @return [String] 'person' or 'organization'
        def entity_type
          return @entity_type if @entity_type && !@entity_type.empty?

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

        # The identifier ItemMapper names this record's file after.
        # @return [String, nil]
        def identifier
          Ammitto::Utils::Presence.presence(generate_id) ||
            Ammitto::Utils::Presence.presence(item)
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
    end
  end
end
