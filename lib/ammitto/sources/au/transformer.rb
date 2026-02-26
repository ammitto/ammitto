# frozen_string_literal: true

require_relative '../../transformers/base_transformer'

module Ammitto
  module Sources
    module Au
      # Transformer converts Australia (DFAT) source models to the harmonized
      # Ammitto ontology models.
      #
      # Australia provides data in XLSX/CSV format with consolidated sanctions.
      # The data includes Individuals, Entities (organizations), and Vessels.
      #
      # Key features:
      # - Reference numbers with suffixes (8577, 8577a, 8577b) represent ONE entity
      # - Name variants include Primary Name, Original Script, and Aliases
      # - Effect flags are boolean columns (Targeted Financial Sanction, etc.)
      #
      # @example Transforming an AU individual
      #   transformer = Ammitto::Sources::Au::Transformer.new
      #   result = transformer.transform(individual)
      #   entity = result[:entity]    # PersonEntity
      #   entry = result[:entry]      # SanctionEntry
      #
      class Transformer < Ammitto::Transformers::BaseTransformer
        # Mapping of Australian committees/regimes to regime codes
        REGIME_MAPPING = {
          '1737 (Iran)' => { code: 'AU_IRAN_1737', name: 'Iran (UNSCR 1737)' },
          '1747 (Iran)' => { code: 'AU_IRAN_1747', name: 'Iran (UNSCR 1747)' },
          'Autonomous (Iran)' => { code: 'AU_IRAN_AUTO', name: 'Iran (Autonomous)' },
          'Autonomous (Vessels)' => { code: 'AU_VESSELS', name: 'Russia Vessels (Autonomous)' },
          'DPRK' => { code: 'AU_DPRK', name: "Democratic People's Republic of Korea" },
          'Russia' => { code: 'AU_RUSSIA', name: 'Russia' },
          'Russia/Ukraine' => { code: 'AU_RUSSIA_UKRAINE', name: 'Russia/Ukraine' },
          'Myanmar' => { code: 'AU_MYANMAR', name: 'Myanmar' },
          'Syria' => { code: 'AU_SYRIA', name: 'Syria' },
          'Libya' => { code: 'AU_LIBYA', name: 'Libya' },
          'Zimbabwe' => { code: 'AU_ZIMBABWE', name: 'Zimbabwe' },
          'Sudan' => { code: 'AU_SUDAN', name: 'Sudan' },
          'Afghanistan' => { code: 'AU_AFGHANISTAN', name: 'Afghanistan' },
          'ISIL (Da\'esh) and Al-Qaida' => { code: 'AU_ISIL', name: 'ISIL (Da\'esh) and Al-Qaida' },
          'Central African Republic' => { code: 'AU_CAR', name: 'Central African Republic' },
          'Democratic Republic of the Congo' => { code: 'AU_DRC', name: 'Democratic Republic of the Congo' },
          'Eritrea' => { code: 'AU_ERITREA', name: 'Eritrea' },
          'Guinea-Bissau' => { code: 'AU_GUINEA_BISSAU', name: 'Guinea-Bissau' },
          'Iran' => { code: 'AU_IRAN', name: 'Iran' },
          'Iraq' => { code: 'AU_IRAQ', name: 'Iraq' },
          'Lebanon' => { code: 'AU_LEBANON', name: 'Lebanon' },
          'Mali' => { code: 'AU_MALI', name: 'Mali' },
          'Mozambique' => { code: 'AU_MOZAMBIQUE', name: 'Mozambique' },
          'Somalia' => { code: 'AU_SOMALIA', name: 'Somalia' },
          'South Sudan' => { code: 'AU_SOUTH_SUDAN', name: 'South Sudan' },
          'Yemen' => { code: 'AU_YEMEN', name: 'Yemen' }
        }.freeze

        def initialize
          super(:au)
        end

        # Transform an AU Individual to ontology models
        # @param individual [Ammitto::Sources::Au::Individual]
        # @return [Hash] { entity: PersonEntity, entry: SanctionEntry }
        def transform_individual(individual)
          entity = create_person_entity(individual)
          entry = create_entry(individual, entity.id)

          entity.add_sanction_entry(entry)

          { entity: entity, entry: entry }
        end

        # Transform an AU Organization to ontology models
        # @param organization [Ammitto::Sources::Au::Organization]
        # @return [Hash] { entity: OrganizationEntity, entry: SanctionEntry }
        def transform_organization(organization)
          entity = create_organization_entity(organization)
          entry = create_entry(organization, entity.id)

          entity.add_sanction_entry(entry)

          { entity: entity, entry: entry }
        end

        # Transform an AU Vessel to ontology models
        # @param vessel [Ammitto::Sources::Au::Vessel]
        # @return [Hash] { entity: VesselEntity, entry: SanctionEntry }
        def transform_vessel(vessel)
          entity = create_vessel_entity(vessel)
          entry = create_entry(vessel, entity.id)

          entity.add_sanction_entry(entry)

          { entity: entity, entry: entry }
        end

        # Generic transform method
        # @param source [Object] AU Individual, Organization, or Vessel
        # @return [Hash]
        def transform(source)
          case source
          when Ammitto::Sources::Au::Individual
            transform_individual(source)
          when Ammitto::Sources::Au::Organization
            transform_organization(source)
          when Ammitto::Sources::Au::Vessel
            transform_vessel(source)
          else
            raise ArgumentError, "Unknown source type: #{source.class}"
          end
        end

        private

        def create_person_entity(individual)
          Ammitto::PersonEntity.new(
            id: generate_entity_id(individual.reference),
            entity_type: 'person',
            names: transform_names(individual.names),
            addresses: transform_address(individual.address),
            birth_info: transform_birth_info(individual),
            nationalities: individual.citizenships,
            remarks: build_remarks(individual)
          )
        end

        def create_organization_entity(organization)
          Ammitto::OrganizationEntity.new(
            id: generate_entity_id(organization.reference),
            entity_type: 'organization',
            names: transform_names(organization.names),
            addresses: transform_address(organization.address),
            remarks: build_remarks(organization)
          )
        end

        def create_vessel_entity(vessel)
          Ammitto::VesselEntity.new(
            id: generate_entity_id(vessel.reference),
            entity_type: 'vessel',
            names: transform_vessel_names(vessel),
            imo_number: vessel.imo_number,
            remarks: build_remarks(vessel)
          )
        end

        def create_entry(source, entity_id)
          sanction = source.sanction
          Ammitto::SanctionEntry.new(
            id: generate_entry_id(source.reference),
            entity_id: entity_id,
            authority: authority,
            regime: transform_regime(sanction&.committees),
            effects: transform_effects(sanction),
            status: 'active',
            reference_number: source.reference,
            period: create_period(listed_date: parse_control_date(sanction&.control_date)),
            legal_bases: transform_legal_instrument(sanction&.instrument),
            raw_source_data: create_raw_source_data(
              source_format: 'csv',
              source_specific_fields: {
                'au:reference' => source.reference,
                'au:committees' => sanction&.committees,
                'au:control_date' => sanction&.control_date,
                'au:instrument' => sanction&.instrument,
                'au:listing_info' => sanction&.listing_information
              }
            )
          )
        end

        def transform_names(name_variants)
          name_variants.map do |nv|
            create_name_variant(
              full_name: nv.text,
              script: nv.script,
              is_primary: nv.primary?
            )
          end
        end

        def transform_vessel_names(vessel)
          names = transform_names(vessel.names)

          # Add previous names as aliases
          vessel.previous_names.each do |prev_name|
            names << create_name_variant(
              full_name: prev_name,
              script: 'Latn',
              is_primary: false
            )
          end

          names
        end

        def transform_address(address_str)
          return [] if address_str.nil? || address_str.empty?

          # Parse address string - format varies
          [create_address(
            street: address_str,
            country: extract_country(address_str)
          )]
        end

        def extract_country(address_str)
          # Try to extract country from address string
          return nil if address_str.nil?

          # Common patterns: "City, Country" or just "Country"
          parts = address_str.split(',').map(&:strip)
          parts.last
        end

        def transform_birth_info(individual)
          dates = individual.dates_of_birth || []
          places = individual.places_of_birth || []

          return [] if dates.empty?

          dates.map.with_index do |dob, idx|
            pob = places[idx] || places.first
            # dob is a FlexibleDate object, use to_date method
            date = dob.respond_to?(:to_date) ? dob.to_date : parse_date(dob)
            create_birth_info(
              date: date,
              city: pob&.city,
              country: pob&.country
            )
          end
        end

        def transform_regime(committees)
          return create_regime(code: 'AU_DFAT', name: 'Australia Sanctions') if committees.nil? || committees.empty?

          # Try to match against known regimes
          REGIME_MAPPING.each do |key, info|
            return create_regime(code: info[:code], name: info[:name]) if committees.include?(key)
          end

          # Use committees as-is if no match
          create_regime(code: committees.upcase.gsub(/[^A-Z0-9]/, '_'), name: committees)
        end

        def transform_effects(effect_flags)
          return [create_effect(effect_type: 'asset_freeze', scope: 'full')] unless effect_flags

          effects = []
          if effect_flags.targeted_financial_sanction
            effects << create_effect(effect_type: 'asset_freeze',
                                     scope: 'full')
          end
          effects << create_effect(effect_type: 'travel_ban', scope: 'full') if effect_flags.travel_ban
          effects << create_effect(effect_type: 'arms_embargo', scope: 'full') if effect_flags.arms_embargo
          if effect_flags.maritime_restriction
            effects << create_effect(effect_type: 'sectoral_sanction', scope: 'full',
                                     description: 'Maritime restriction')
          end

          effects.empty? ? [create_effect(effect_type: 'asset_freeze', scope: 'full')] : effects
        end

        def transform_legal_instrument(instrument_str)
          return [] if instrument_str.nil? || instrument_str.empty?

          [Ammitto::LegalInstrument.new(
            type: detect_instrument_type(instrument_str),
            identifier: instrument_str,
            title: instrument_str
          )]
        end

        def detect_instrument_type(instrument_str)
          case instrument_str.downcase
          when /regulation/
            'regulation'
          when /act/
            'act'
          when /instrument/
            'instrument'
          when /charter/
            'resolution'
          else
            'regulation'
          end
        end

        def parse_control_date(date_str)
          return nil if date_str.nil? || date_str.empty?

          # Format: "2/2/26" or "6/18/25"
          begin
            parts = date_str.split('/')
            if parts.length == 3
              month = parts[0].to_i
              day = parts[1].to_i
              year = parts[2].to_i
              year += 2000 if year < 100
              Date.new(year, month, day)
            end
          rescue Date::Error
            nil
          end
        end

        def build_remarks(source)
          parts = []
          parts << source.additional_info if source.additional_info && !source.additional_info.empty?
          listing_info = source.sanction&.listing_information
          parts << "Listing: #{listing_info}" if listing_info && !listing_info.empty?
          parts.join('; ')
        end
      end
    end
  end
end

# Backward compatibility alias
Ammitto::Transformers::AuTransformer = Ammitto::Sources::Au::Transformer
