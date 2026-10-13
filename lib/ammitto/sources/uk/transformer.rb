# frozen_string_literal: true

require_relative '../../transformers/base_transformer'

module Ammitto
  module Sources
    module Uk
      # Transformer converts UK OFSI source models to the harmonized
      # Ammitto ontology models.
      #
      # @example Transforming a UK designation
      #   transformer = Ammitto::Sources::Uk::Transformer.new
      #   result = transformer.transform(designation)
      #   entity = result[:entity]    # PersonEntity or OrganizationEntity
      #   entry = result[:entry]      # SanctionEntry
      #
      class Transformer < Ammitto::Transformers::BaseTransformer
        # Mapping of UK regime names to codes
        REGIME_CODES = {
          'Russia' => 'RUSSIA',
          "Democratic People's Republic of Korea" => 'DPRK',
          'DPRK' => 'DPRK',
          'Iran' => 'IRAN',
          'Syria' => 'SYRIA',
          'Al-Qaida' => 'AL-QAIDA',
          'Taliban' => 'TALIBAN',
          'Yemen' => 'YEMEN',
          'Libya' => 'LIBYA',
          'Somalia' => 'SOMALIA',
          'Sudan' => 'SUDAN',
          'Myanmar' => 'MYANMAR',
          'Belarus' => 'BELARUS',
          'Zimbabwe' => 'ZIMBABWE',
          'Venezuela' => 'VENEZUELA',
          'Iraq' => 'IRAQ',
          'Tunisia' => 'TUNISIA',
          'Egypt' => 'EGYPT',
          'Ukraine' => 'UKRAINE',
          'Mali' => 'MALI',
          'Central African Republic' => 'CAR',
          'Democratic Republic of the Congo' => 'DRC',
          'South Sudan' => 'SOUTH_SUDAN',
          'Ethiopia' => 'ETHIOPIA',
          'Moldova' => 'MOLDOVA',
          'Cyprus' => 'CYPRUS',
          'Haiti' => 'HAITI',
          'Guinea' => 'GUINEA',
          'Burma' => 'MYANMAR',
          'Hezbollah' => 'HEZBOLLAH',
          'ISIL (Daesh)' => 'ISIL',
          'Terrorism' => 'TERRORISM'
        }.freeze

        def initialize
          super(:uk)
        end

        # Transform a UK Designation to ontology models
        # @param designation [Ammitto::Sources::Uk::Designation] the UK designation
        # @return [Hash] { entity: Entity, entry: SanctionEntry }
        def transform(designation)
          @current_designation = designation

          entity = create_entity(designation)
          entry = create_entry(designation)

          # Link entity to entry
          entity.add_sanction_entry(entry)

          {
            entity: entity,
            entry: entry
          }
        ensure
          @current_designation = nil
        end

        # Create the appropriate entity type based on designation
        # @param designation [Ammitto::Sources::Uk::Designation]
        # @return [PersonEntity, OrganizationEntity, VesselEntity]
        def create_entity(designation)
          if designation.individual?
            create_person_entity(designation)
          elsif designation.ship?
            create_vessel_entity(designation)
          else
            create_organization_entity(designation)
          end
        end

        # Create a PersonEntity from a UK designation
        # @param designation [Ammitto::Sources::Uk::Designation]
        # @return [PersonEntity]
        def create_person_entity(designation)
          Ammitto::PersonEntity.new(
            id: generate_entity_id(designation.unique_id),
            entity_type: 'person',
            names: transform_names(designation),
            addresses: transform_addresses(designation.addresses),
            birth_info: transform_birth_info(designation.individual_details),
            nationalities: transform_nationalities(designation.individual_details),
            gender: designation.individual_details&.genders&.first,
            identifications: transform_identifications(designation.individual_details),
            title: extract_title(designation),
            position: extract_position(designation.individual_details),
            remarks: designation.other_information
          )
        end

        # Create an OrganizationEntity from a UK designation
        # @param designation [Ammitto::Sources::Uk::Designation]
        # @return [OrganizationEntity]
        def create_organization_entity(designation)
          Ammitto::OrganizationEntity.new(
            id: generate_entity_id(designation.unique_id),
            entity_type: 'organization',
            names: transform_names(designation),
            addresses: transform_addresses(designation.addresses),
            remarks: designation.other_information
          )
        end

        # Create a VesselEntity from a UK ship designation
        # @param designation [Ammitto::Sources::Uk::Designation]
        # @return [VesselEntity]
        def create_vessel_entity(designation)
          ship = designation.ship_details&.ship

          Ammitto::VesselEntity.new(
            id: generate_entity_id(designation.unique_id),
            entity_type: 'vessel',
            names: transform_names(designation),
            imo_number: normalize_imo(ship&.imo_numbers&.first),
            flag_state: ship&.current_believed_flags&.first,
            previous_flags: ship&.previous_flags || [],
            vessel_type: ship&.types_of_ship&.first,
            build_year: parse_build_year(ship&.years_built&.first),
            remarks: designation.other_information
          )
        end

        # Create a SanctionEntry from a UK designation
        # @param designation [Ammitto::Sources::Uk::Designation]
        # @return [SanctionEntry]
        def create_entry(designation)
          Ammitto::SanctionEntry.new(
            id: generate_entry_id(designation.unique_id),
            entity_id: generate_entity_id(designation.unique_id),
            authority: authority,
            regime: transform_regime(designation.regime_name),
            effects: transform_effects(designation.sanctions_imposed_indicators),
            period: create_period(
              source: :uk,
              listed_date: designation.date_designated,
              effective_date: designation.date_designated,
              last_updated: designation.last_updated
            ),
            status: 'active',
            reference_number: designation.unique_id,
            remarks: designation.uk_statement_of_reasons,
            raw_source_data: create_raw_source_data(
              source_format: 'xml',
              source_specific_fields: {
                'uk:ofsiGroupId' => designation.ofsi_group_id,
                'uk:unReferenceNumber' => designation.un_reference_number,
                'uk:designationSource' => designation.designation_source,
                'uk:sanctionsImposed' => designation.sanctions_imposed,
                'uk:entityType' => designation.individual_entity_ship
              }
            )
          )
        end

        # Transform UK names to NameVariant objects
        # @param designation [Ammitto::Sources::Uk::Designation]
        # @return [Array<NameVariant>]
        def transform_names(designation)
          # Primary and alias names
          names = designation.names.map do |name|
            create_name_variant(
              full_name: name.full_name,
              first_name: name.name1,
              is_primary: name.primary_name?,
              script: 'Latn'
            )
          end

          # Non-Latin names (aliases in other scripts)
          designation.non_latin_names.each do |name|
            names << create_name_variant(
              full_name: name.name_non_latin_script,
              is_primary: false,
              script: detect_script(name.name_non_latin_script)
            )
          end

          names
        end

        # Transform UK addresses to Address objects
        # @param addresses [Array<Ammitto::Sources::Uk::Address>]
        # @return [Array<Address>]
        def transform_addresses(addresses)
          addresses.map do |addr|
            create_address(
              street: addr.street,
              city: addr.city,
              state: addr.state,
              country: addr.country
            )
          end
        end

        # Transform individual details to BirthInfo objects
        # @param details [Ammitto::Sources::Uk::IndividualDetails, nil]
        # @return [Array<BirthInfo>]
        def transform_birth_info(details)
          return [] unless details

          birth_infos = []

          # From DOBs
          details.dobs.each do |dob_str|
            next if dob_str.nil? || dob_str.include?('dd/mm') # Skip placeholders

            birth_location = details.birth_details&.primary_location

            birth_date = analyze_birth_date(
              dob_str,
              parser: method(:parse_uk_date)
            )

            # A partial DOB ("00/00/1975", "1975-00-00") keeps its year;
            # only a fully stated day-month-year becomes a date
            birth_infos << create_birth_info(
              **birth_date,
              city: birth_location&.town_of_birth,
              country: birth_location&.country_of_birth
            )
          end

          # If no DOB but has birth location
          if birth_infos.empty? && details.birth_details&.primary_location
            loc = details.birth_details.primary_location
            birth_infos << create_birth_info(
              city: loc.town_of_birth,
              country: loc.country_of_birth
            )
          end

          birth_infos
        end

        # Transform nationalities
        # @param details [Ammitto::Sources::Uk::IndividualDetails, nil]
        # @return [Array<String>]
        def transform_nationalities(details)
          return [] unless details

          details.nationalities.compact
        end

        # Transform passports and national identifiers to Identification
        # objects
        # @param details [Ammitto::Sources::Uk::IndividualDetails, nil]
        # @return [Array<Identification>]
        def transform_identifications(details)
          return [] unless details

          passports = details.passports.map do |passport|
            create_identification(
              type: 'Passport',
              number: passport.number,
              note: passport.additional_information
            )
          end
          national_ids = details.national_identifiers.map do |identifier|
            create_identification(
              type: 'NationalID',
              number: identifier.number,
              note: identifier.additional_information
            )
          end

          (passports + national_ids).uniq do |id|
            [id.type, id.number, id.note]
          end
        end

        # Honorifics OFSI lists on the designation, such as Mullah or Haji
        # @param designation [Ammitto::Sources::Uk::Designation]
        # @return [String, nil]
        def extract_title(designation)
          titles = designation.titles
          return nil if titles.nil? || titles.empty?

          titles.join(', ')
        end

        # OFSI writes IMO numbers both as "IMO9562233" and "9562233"
        # @param value [String, nil]
        # @return [String, nil]
        def normalize_imo(value)
          return nil if value.nil?

          imo = value.strip.sub(/\AIMO\s*/i, '')
          imo.empty? ? nil : imo
        end

        # @param value [String, nil]
        # @return [Integer, nil]
        def parse_build_year(value)
          return nil unless value&.match?(/\A\d{4}\z/)

          value.to_i
        end

        # Extract position from individual details
        # @param details [Ammitto::Sources::Uk::IndividualDetails, nil]
        # @return [String, nil]
        def extract_position(details)
          return nil unless details

          details.positions&.first
        end

        # Transform UK regime name to SanctionRegime
        # @param regime_name [String, nil]
        # @return [SanctionRegime]
        def transform_regime(regime_name)
          code = REGIME_CODES[regime_name] || normalize_regime_code(regime_name)

          create_regime(
            name: regime_name,
            code: code
          )
        end

        # Transform UK sanctions indicators to SanctionEffect objects
        # @param indicators [Ammitto::Sources::Uk::SanctionsIndicators, nil]
        # @return [Array<SanctionEffect>]
        def transform_effects(indicators)
          return [] unless indicators

          indicators.to_effect_types.map do |effect_hash|
            create_effect(
              effect_type: effect_hash[:type],
              scope: effect_hash[:scope] || 'full'
            )
          end
        end

        # Parse UK date format (DD/MM/YYYY), yielding a Date only for a
        # complete day-month-year
        # @param date_str [String]
        # @return [Date, nil]
        def parse_uk_date(date_str)
          return nil if date_str.nil? || date_str.empty?

          # Try DD/MM/YYYY format first
          if date_str.match(%r{\d{1,2}/\d{1,2}/\d{4}})
            begin
              Date.strptime(date_str, '%d/%m/%Y')
            rescue Date::Error
              parse_complete_date(date_str) # Fall back to standard parsing
            end
          else
            parse_complete_date(date_str)
          end
        end

        # Normalize regime name to a code
        # @param regime_name [String, nil]
        # @return [String, nil]
        def normalize_regime_code(regime_name)
          return nil if regime_name.nil? || regime_name.empty?

          regime_name
            .upcase
            .gsub(/[^A-Z0-9]/, '_')
            .gsub(/_+/, '_')
            .gsub(/^_|_$/, '')
        end

        # Detect script from text
        # @param text [String, nil]
        # @return [String]
        def detect_script(text)
          return 'Latn' if text.nil? || text.empty?

          # Cyrillic
          return 'Cyrl' if text.match?(/\p{Cyrillic}/)

          # Arabic
          return 'Arab' if text.match?(/\p{Arabic}/)

          # Chinese/Japanese/Korean
          return 'Hani' if text.match?(/\p{Han}/)

          # Default to Latin
          'Latn'
        end
      end
    end
  end
end

# Backward compatibility alias
Ammitto::Transformers::UkTransformer = Ammitto::Sources::Uk::Transformer
