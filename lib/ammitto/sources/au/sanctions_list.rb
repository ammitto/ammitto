# frozen_string_literal: true

require 'lutaml/model'
require 'csv'

module Ammitto
  module Sources
    module Au
      # Australian DFAT Sanctions Ontology
      # ================================
      #
      # This module provides a fully normalized ontology for Australian sanctions
      # data from the Department of Foreign Affairs and Trade (DFAT).
      #
      # Source: https://www.dfat.gov.au/sites/default/files/Australian_Sanctions_Consolidated_List.xlsx
      #
      # == Ontology Overview
      #
      # The Australian sanctions ontology consists of these core concepts:
      #
      # 1. Entity - The sanctioned party (Individual, Organization, or Vessel)
      # 2. Name - Name variants with script and type information
      # 3. Sanction - The sanctions imposed (effects, regime, legal basis)
      # 4. Legal Instrument - The law/regulation authorizing the sanction
      # 5. Regime - The sanctions program (UN, autonomous, country-specific)
      #
      # == Data Normalization
      #
      # The CSV data has a denormalized structure where one entity can span
      # multiple rows (for different name variants). This ontology normalizes
      # that data into proper objects:
      #
      #   CSV Row 1: 8577, Mohammad Salah JOKAR, Primary Name, ...
      #   CSV Row 2: 8577a, محمد صالح جوکار, Original Script, ...
      #   CSV Row 3: 8577b, Mohammad Saleh JOKAR, Alias, Strong, ...
      #
      # Becomes ONE SanctionedIndividual with three Name objects.
      #
      # == Entity Types
      #
      # - Individual: A natural person with birth info, citizenship
      # - Organization: A legal entity (company, group, institution)
      # - Vessel: A ship with IMO number, flag state, tonnage
      #
      # == Sanction Effects
      #
      # Australia imposes four types of sanctions measures:
      #
      # - Targeted Financial Sanction: Asset freeze, transaction prohibitions
      # - Travel Ban: Entry restrictions, visa prohibitions
      # - Arms Embargo: Weapons trade restrictions
      # - Maritime Restriction: Shipping/port access restrictions
      #
      # == Regime Types
      #
      # Australian sanctions fall into categories:
      #
      # - UN Security Council: Implemented under UNSC resolutions
      #   - 1737 (Iran), 1718 (DPRK), etc.
      # - Autonomous: Australia-specific sanctions
      #   - Autonomous (Iran), Autonomous (Russia), etc.
      # - Country-specific: Targeted at specific nations
      #
      # @example Parsing CSV data
      #   csv = File.read('Australian_Sanctions_Consolidated_List.csv')
      #   list = SanctionsList.from_csv(csv)
      #
      #   list.individuals.each do |person|
      #     puts person.reference
      #     puts person.primary_name
      #     puts person.names.map(&:name)
      #     puts person.sanction.effects.map(&:type)
      #   end
      #

      # ============================================================
      # ENUMERATIONS
      # ============================================================

      # Entity type enumeration
      module EntityType
        INDIVIDUAL = 'Individual'
        ORGANIZATION = 'Entity' # NOTE: CSV uses "Entity" not "Organization"
        VESSEL = 'Vessel'

        ALL = [INDIVIDUAL, ORGANIZATION, VESSEL].freeze

        def self.from_csv(value)
          return nil if value.nil? || value.empty?
          return value if ALL.include?(value)

          # Fallback mapping
          case value.downcase
          when 'individual', 'person'
            INDIVIDUAL
          when 'entity', 'organization', 'company'
            ORGANIZATION
          when 'vessel', 'ship'
            VESSEL
          else
            value
          end
        end
      end

      # Name type enumeration
      module NameType
        PRIMARY = 'Primary Name'
        ORIGINAL_SCRIPT = 'Original Script'
        ALIAS = 'Alias'

        ALL = [PRIMARY, ORIGINAL_SCRIPT, ALIAS].freeze

        def self.from_csv(value)
          return nil if value.nil? || value.empty?

          value
        end
      end

      # Alias strength enumeration
      module AliasStrength
        STRONG = 'Strong'
        WEAK = 'Weak'

        ALL = [STRONG, WEAK].freeze

        def self.from_csv(value)
          return nil if value.nil? || value.empty?
          return value if ALL.include?(value)

          case value.downcase
          when 'strong'
            STRONG
          when 'weak'
            WEAK
          else
            value
          end
        end
      end

      # Script enumeration (ISO 15924)
      module Script
        LATN = 'Latn'      # Latin
        ARAB = 'Arab'      # Arabic
        CYRL = 'Cyrl'      # Cyrillic
        HANI = 'Hani'      # Han (Chinese)
        HEBR = 'Hebr'      # Hebrew
        GREK = 'Grek'      # Greek
        DEVA = 'Deva'      # Devanagari
        THAI = 'Thai'      # Thai
        JPAN = 'Jpan'      # Japanese
        KORE = 'Kore'      # Korean

        def self.detect(text)
          return LATN if text.nil? || text.empty?

          case text
          when /[\u0600-\u06FF]/ then ARAB  # Arabic
          when /[\u0400-\u04FF]/ then CYRL  # Cyrillic
          when /[\u4E00-\u9FFF]/ then HANI  # Chinese
          when /[\u0590-\u05FF]/ then HEBR  # Hebrew
          when /[\u0370-\u03FF]/ then GREK  # Greek
          when /[\u0900-\u097F]/ then DEVA  # Devanagari
          when /[\u0E00-\u0E7F]/ then THAI  # Thai
          when /[\u3040-\u309F]/ then JPAN  # Hiragana
          when /[\u30A0-\u30FF]/ then JPAN  # Katakana
          when /[\uAC00-\uD7AF]/ then KORE  # Korean
          else LATN
          end
        end
      end

      # Sanction effect type enumeration
      module EffectType
        TARGETED_FINANCIAL_SANCTION = 'targeted_financial_sanction'
        TRAVEL_BAN = 'travel_ban'
        ARMS_EMBARGO = 'arms_embargo'
        MARITIME_RESTRICTION = 'maritime_restriction'

        # Mapping to Ammitto ontology effect types
        TO_AMMITTO = {
          TARGETED_FINANCIAL_SANCTION => 'asset_freeze',
          TRAVEL_BAN => 'travel_ban',
          ARMS_EMBARGO => 'arms_embargo',
          MARITIME_RESTRICTION => 'sectoral_sanction'
        }.freeze
      end

      # ============================================================
      # VALUE OBJECTS
      # ============================================================

      # ISO 8601 date with support for partial/imprecise dates
      class FlexibleDate < Lutaml::Model::Serializable
        attribute :raw_value, :string    # Original value from CSV
        attribute :year, :integer
        attribute :month, :integer
        attribute :day, :integer
        attribute :circa, :boolean       # Approximate date
        attribute :precision, :string    # 'full', 'month', 'year', 'circa'

        def self.parse(date_str)
          return nil if date_str.nil? || date_str.empty?

          flexible = new(raw_value: date_str, precision: 'full')

          # Handle various date formats
          # "5 May 1957", "April 1957", "1957", "circa 1957"

          cleaned = date_str.strip.downcase

          if cleaned.start_with?('circa', 'c.', 'c')
            flexible.circa = true
            flexible.precision = 'circa'
            cleaned = cleaned.sub(/^circa\s*|^c\.\s*|^c\s*/, '')
          end

          # Try full date: "5 May 1957" or "May 5, 1957"
          if (match = cleaned.match(/(\d{1,2})\s+(\w+)\s+(\d{4})/))
            flexible.day = match[1].to_i
            flexible.month = parse_month(match[2])
            flexible.year = match[3].to_i
          elsif (match = cleaned.match(/(\w+)\s+(\d{1,2}),?\s+(\d{4})/))
            flexible.month = parse_month(match[1])
            flexible.day = match[2].to_i
            flexible.year = match[3].to_i
          elsif (match = cleaned.match(/(\w+)\s+(\d{4})/))
            # Month and year only: "May 1957"
            flexible.month = parse_month(match[1])
            flexible.year = match[2].to_i
            flexible.precision = 'month' unless flexible.circa
            flexible.day = nil
          elsif (match = cleaned.match(/(\d{4})/))
            # Year only: "1957"
            flexible.year = match[1].to_i
            flexible.precision = 'year' unless flexible.circa
          end

          flexible
        end

        def self.parse_month(month_str)
          months = %w[january february march april may june july august september october november december]
          idx = months.index(month_str.downcase)
          idx ? idx + 1 : 0
        end

        def to_date
          return nil unless year
          return nil if precision == 'year' && !month

          begin
            Date.new(year, month || 1, day || 1)
          rescue StandardError
            nil
          end
        end

        def to_s
          raw_value
        end
      end

      # Geographic location
      class Location < Lutaml::Model::Serializable
        attribute :raw_value, :string
        attribute :city, :string
        attribute :region, :string # State, province
        attribute :country, :string

        def self.parse(location_str)
          return nil if location_str.nil? || location_str.empty?

          location = new(raw_value: location_str.strip)

          # Try to parse "City, Region, Country" format
          parts = location_str.split(',').map(&:strip)

          case parts.length
          when 1
            # Just a city or country
            location.country = parts[0]
          when 2
            location.city = parts[0]
            location.country = parts[1]
          when 3
            location.city = parts[0]
            location.region = parts[1]
            location.country = parts[2]
          else
            location.raw_value = location_str
          end

          location
        end

        def to_s
          raw_value
        end
      end

      # ============================================================
      # NAME MODEL
      # ============================================================

      # Name variant with type, script, and strength information
      class Name < Lutaml::Model::Serializable
        attribute :text, :string           # The name text
        attribute :name_type, :string      # Primary Name, Original Script, Alias
        attribute :script, :string         # ISO 15924 script code
        attribute :alias_strength, :string # Strong, Weak, or nil

        def primary?
          name_type == NameType::PRIMARY
        end

        def original_script?
          name_type == NameType::ORIGINAL_SCRIPT
        end

        def alias?
          name_type == NameType::ALIAS
        end

        def strong_alias?
          alias? && alias_strength == AliasStrength::STRONG
        end

        def weak_alias?
          alias? && alias_strength == AliasStrength::WEAK
        end

        def self.from_csv(name_text, name_type, alias_strength)
          new(
            text: name_text,
            name_type: NameType.from_csv(name_type),
            script: Script.detect(name_text),
            alias_strength: AliasStrength.from_csv(alias_strength)
          )
        end
      end

      # ============================================================
      # SANCTION MODEL
      # ============================================================

      # Sanction measures imposed on an entity
      class Sanction < Lutaml::Model::Serializable
        attribute :listing_information, :string
        attribute :committees, :string           # UN committee or regime
        attribute :control_date, :string         # Date added to list
        attribute :instrument, :string           # Legal instrument
        attribute :targeted_financial_sanction, :boolean
        attribute :travel_ban, :boolean
        attribute :arms_embargo, :boolean
        attribute :maritime_restriction, :boolean

        def effects
          effects = []
          effects << EffectType::TARGETED_FINANCIAL_SANCTION if targeted_financial_sanction
          effects << EffectType::TRAVEL_BAN if travel_ban
          effects << EffectType::ARMS_EMBARGO if arms_embargo
          effects << EffectType::MARITIME_RESTRICTION if maritime_restriction
          effects
        end

        def has_effects?
          effects.any?
        end

        def regime_type
          return nil if committees.nil? || committees.empty?

          # Parse regime type from committees field
          if committees.include?('Autonomous')
            :autonomous
          elsif committees.match?(/\d{4}/)
            :un_security_council
          else
            :other
          end
        end

        def to_ammitto_effect_types
          effects.map { |e| EffectType::TO_AMMITTO[e] }.compact
        end
      end

      # ============================================================
      # ENTITY BASE CLASS
      # ============================================================

      # Base class for all sanctioned entities
      class BaseEntity < Lutaml::Model::Serializable
        attribute :reference, :string # Base reference number
        attribute :names, Name, collection: true
        attribute :address, :string
        attribute :additional_info, :string
        attribute :sanction, Sanction

        # Parse base reference number (strip suffix letters)
        # "8577" -> "8577", "8577a" -> "8577", "8577bcd" -> "8577"
        def self.parse_base_reference(ref)
          match = ref.to_s.match(/^(\d+)/)
          match ? match[1] : ref.to_s
        end

        def primary_name
          names.find(&:primary?)&.text || names.first&.text
        end

        def original_script_name
          names.find(&:original_script?)&.text
        end

        def aliases
          names.select(&:alias?)
        end

        def strong_aliases
          names.select(&:strong_alias?)
        end

        def weak_aliases
          names.select(&:weak_alias?)
        end

        def add_name(name)
          return if name.nil? || name.text.nil? || name.text.empty?
          return if names.any? { |n| n.text == name.text }

          names << name
        end

        def entity_type
          raise NotImplementedError, 'Subclasses must implement entity_type'
        end

        def merge_row(row)
          # Add name variant
          name = Name.from_csv(
            row['Name of Individual or Entity'],
            row['Name Type'],
            row['Alias Strength']
          )
          add_name(name)

          # Update sanction info (should be same for all rows)
          self.sanction ||= build_sanction(row)
        end

        private

        def build_sanction(row)
          Sanction.new(
            listing_information: row['Listing Information'],
            committees: row['Committees'],
            control_date: row['Control Date'],
            instrument: row['Instrument of Designation'],
            targeted_financial_sanction: parse_bool(row['Targeted Financial Sanction']),
            travel_ban: parse_bool(row['Travel Ban']),
            arms_embargo: parse_bool(row['Arms Embargo']),
            maritime_restriction: parse_bool(row['Maritime Restriction'])
          )
        end

        def parse_bool(value)
          value.to_s.upcase == 'TRUE'
        end
      end

      # ============================================================
      # INDIVIDUAL ENTITY
      # ============================================================

      # Sanctioned individual (natural person)
      class Individual < BaseEntity
        attribute :dates_of_birth, FlexibleDate, collection: true
        attribute :places_of_birth, Location, collection: true
        attribute :citizenships, :string, collection: true

        def entity_type
          EntityType::INDIVIDUAL
        end

        def birth_years
          dates_of_birth.map(&:year).compact.uniq
        end

        def birth_countries
          places_of_birth.map(&:country).compact.uniq
        end

        def merge_row(row)
          super

          # Parse dates of birth (comma-separated, can have multiple)
          dob_str = row['Date of Birth']
          if dob_str && !dob_str.empty?
            dob_str.split(',').map(&:strip).each do |date_str|
              date = FlexibleDate.parse(date_str)
              dates_of_birth << date if date && dates_of_birth.none? { |d| d.raw_value == date.raw_value }
            end
          end

          # Parse places of birth (comma-separated)
          pob_str = row['Place of Birth']
          if pob_str && !pob_str.empty?
            pob_str.split(',').map(&:strip).each do |loc_str|
              next if loc_str.empty?

              loc = Location.parse(loc_str)
              places_of_birth << loc if loc && places_of_birth.none? { |p| p.raw_value == loc.raw_value }
            end
          end

          # Parse citizenships (comma-separated)
          cit_str = row['Citizenship']
          return unless cit_str && !cit_str.empty?

          cit_str.split(',').map(&:strip).reject(&:empty?).each do |cit|
            citizenships << cit unless citizenships.include?(cit)
          end
        end

        def self.from_csv_row(row)
          entity = new(
            reference: parse_base_reference(row['Reference']),
            names: [],
            address: row['Address'],
            additional_info: row['Additional Information'],
            sanction: nil,
            dates_of_birth: [],
            places_of_birth: [],
            citizenships: []
          )
          entity.merge_row(row)
          entity
        end
      end

      # ============================================================
      # ORGANIZATION ENTITY
      # ============================================================

      # Sanctioned organization (legal entity)
      class Organization < BaseEntity
        def entity_type
          EntityType::ORGANIZATION
        end

        def self.from_csv_row(row)
          entity = new(
            reference: parse_base_reference(row['Reference']),
            names: [],
            address: row['Address'],
            additional_info: row['Additional Information'],
            sanction: nil
          )
          entity.merge_row(row)
          entity
        end
      end

      # ============================================================
      # VESSEL ENTITY
      # ============================================================

      # Sanctioned vessel (ship)
      class Vessel < BaseEntity
        attribute :imo_number, :string
        attribute :previous_names, :string, collection: true

        def entity_type
          EntityType::VESSEL
        end

        def self.from_csv_row(row)
          entity = new(
            reference: parse_base_reference(row['Reference']),
            names: [],
            address: nil, # Vessels don't have addresses
            additional_info: row['Additional Information'],
            sanction: nil,
            imo_number: row['IMO Number'],
            previous_names: []
          )
          entity.merge_row(row)

          # Parse previous names from additional info
          entity.extract_previous_names

          entity
        end

        def extract_previous_names
          return unless additional_info&.include?('Previous names include')

          match = additional_info.match(/Previous names include\s+(.+?)(?:\.|$)/)
          return unless match

          match[1].split(',').map(&:strip).reject(&:empty?).each do |name|
            previous_names << name unless previous_names.include?(name)
          end
        end
      end

      # ============================================================
      # SANCTIONS LIST (COLLECTION)
      # ============================================================

      # Collection of all sanctioned entities from the CSV
      class SanctionsList < Lutaml::Model::Serializable
        attribute :individuals, Individual, collection: true
        attribute :organizations, Organization, collection: true
        attribute :vessels, Vessel, collection: true

        # Module-level method for parse_base_reference
        def self.parse_base_reference(ref)
          BaseEntity.parse_base_reference(ref)
        end

        # Parse from CSV content
        # @param csv_content [String] CSV content
        # @return [SanctionsList]
        def self.from_csv(csv_content)
          list = new(individuals: [], organizations: [], vessels: [])

          # Track entities by base reference to merge rows
          individuals_map = {}
          organizations_map = {}
          vessels_map = {}

          CSV.parse(csv_content, headers: true) do |row|
            next unless row['Reference']

            entity_type = EntityType.from_csv(row['Type'])
            base_ref = parse_base_reference(row['Reference'])

            case entity_type
            when EntityType::INDIVIDUAL
              if individuals_map[base_ref]
                individuals_map[base_ref].merge_row(row)
              else
                entity = Individual.from_csv_row(row)
                individuals_map[base_ref] = entity
                list.individuals << entity
              end
            when EntityType::ORGANIZATION
              if organizations_map[base_ref]
                organizations_map[base_ref].merge_row(row)
              else
                entity = Organization.from_csv_row(row)
                organizations_map[base_ref] = entity
                list.organizations << entity
              end
            when EntityType::VESSEL
              if vessels_map[base_ref]
                vessels_map[base_ref].merge_row(row)
              else
                entity = Vessel.from_csv_row(row)
                vessels_map[base_ref] = entity
                list.vessels << entity
              end
            end
          end

          list
        end

        def all_entities
          individuals + organizations + vessels
        end

        def count
          individuals.size + organizations.size + vessels.size
        end

        def count_by_regime
          all_entities.group_by { |e| e.sanction&.committees }
                      .transform_values(&:count)
        end

        def count_by_effect
          counts = Hash.new(0)
          all_entities.each do |entity|
            entity.sanction&.effects&.each do |effect|
              counts[effect] += 1
            end
          end
          counts
        end
      end
    end
  end
end
