# frozen_string_literal: true

require_relative '../../transformers/base_transformer'

module Ammitto
  module Sources
    module Eu
      # Transformer converts EU source models to the harmonized
      # Ammitto ontology models.
      #
      # @example Transforming an EU sanction entity
      #   transformer = Ammitto::Sources::Eu::Transformer.new
      #   result = transformer.transform(sanction_entity)
      #   entity = result[:entity]    # PersonEntity or OrganizationEntity
      #   entry = result[:entry]      # SanctionEntry
      #
      class Transformer < Ammitto::Transformers::BaseTransformer
        # Mapping of EU programme codes to regime info
        REGIME_MAPPING = {
          'IRQ' => { code: 'IRQ', name: 'Iraq' },
          'DPRK' => { code: 'DPRK', name: "Democratic People's Republic of Korea" },
          'IRN' => { code: 'IRAN', name: 'Iran' },
          'IRAN' => { code: 'IRAN', name: 'Iran' },
          'SYR' => { code: 'SYRIA', name: 'Syria' },
          'LBY' => { code: 'LIBYA', name: 'Libya' },
          'SOM' => { code: 'SOMALIA', name: 'Somalia' },
          'SDN' => { code: 'SUDAN', name: 'Sudan' },
          'AFG' => { code: 'AFGHANISTAN', name: 'Afghanistan' },
          'MLI' => { code: 'MALI', name: 'Mali' },
          'YEM' => { code: 'YEMEN', name: 'Yemen' },
          'GIN' => { code: 'GUINEA', name: 'Guinea' },
          'BDI' => { code: 'BURUNDI', name: 'Burundi' },
          'CAF' => { code: 'CAR', name: 'Central African Republic' },
          'COD' => { code: 'DRC', name: 'Democratic Republic of the Congo' },
          'TUN' => { code: 'TUNISIA', name: 'Tunisia' },
          'UKR' => { code: 'RUSSIA', name: 'Russia/Ukraine' },
          'RUS' => { code: 'RUSSIA', name: 'Russia/Ukraine' },
          'BLR' => { code: 'BELARUS', name: 'Belarus' },
          'VEN' => { code: 'VENEZUELA', name: 'Venezuela' },
          'MOZ' => { code: 'MOZAMBIQUE', name: 'Mozambique' },
          'ETH' => { code: 'ETHIOPIA', name: 'Ethiopia' },
          'HTI' => { code: 'HAITI', name: 'Haiti' },
          'MMR' => { code: 'MYANMAR', name: 'Myanmar' },
          'AL-QAIDA' => { code: 'AL-QAIDA', name: 'Al-Qaida' },
          'TAHBAN' => { code: 'TALIBAN', name: 'Taliban' },
          'ISIL' => { code: 'ISIL', name: 'ISIL (Daesh)' }
        }.freeze

        def initialize
          super(:eu)
        end

        # Transform an EU SanctionEntity to ontology models
        # @param entity [Ammitto::Sources::Eu::SanctionEntity] the EU sanction entity
        # @return [Hash] { entity: Entity, entry: SanctionEntry }
        def transform(entity)
          @current_entity = entity

          ont_entity = create_entity(entity)
          entry = create_entry(entity)

          # Link entity to entry
          ont_entity.add_sanction_entry(entry)

          {
            entity: ont_entity,
            entry: entry
          }
        ensure
          @current_entity = nil
        end

        private

        # Create the appropriate entity type based on subject type
        # @param entity [Ammitto::Sources::Eu::SanctionEntity]
        # @return [PersonEntity, OrganizationEntity]
        def create_entity(entity)
          if entity.person?
            create_person_entity(entity)
          else
            create_organization_entity(entity)
          end
        end

        # Create a PersonEntity from an EU sanction entity
        # @param entity [Ammitto::Sources::Eu::SanctionEntity]
        # @return [PersonEntity]
        def create_person_entity(entity)
          Ammitto::PersonEntity.new(
            id: generate_entity_id(entity.eu_reference_number),
            entity_type: 'person',
            names: transform_names(entity.name_aliases),
            addresses: transform_addresses(entity.addresses),
            birth_info: transform_birthdates(entity.birthdates),
            nationalities: entity.nationalities,
            gender: entity.gender,
            identifications: transform_identifications(entity.identifications),
            remarks: entity.remark
          )
        end

        # Create an OrganizationEntity from an EU sanction entity
        # @param entity [Ammitto::Sources::Eu::SanctionEntity]
        # @return [OrganizationEntity]
        def create_organization_entity(entity)
          Ammitto::OrganizationEntity.new(
            id: generate_entity_id(entity.eu_reference_number),
            entity_type: 'organization',
            names: transform_names(entity.name_aliases),
            addresses: transform_addresses(entity.addresses),
            identifications: transform_identifications(entity.identifications),
            remarks: entity.remark
          )
        end

        # Create a SanctionEntry from an EU sanction entity
        # @param entity [Ammitto::Sources::Eu::SanctionEntity]
        # @return [SanctionEntry]
        def create_entry(entity)
          regulation = entity.primary_regulation

          Ammitto::SanctionEntry.new(
            id: generate_entry_id(entity.eu_reference_number),
            entity_id: generate_entity_id(entity.eu_reference_number),
            authority: authority,
            regime: transform_regime(entity.programme),
            legal_bases: transform_regulations(entity.regulations),
            effects: create_default_effects,
            period: create_period(
              listed_date: regulation&.publication_date,
              effective_date: regulation&.entry_into_force_date
            ),
            status: 'active',
            reference_number: entity.eu_reference_number,
            remarks: entity.remark,
            raw_source_data: create_raw_source_data(
              source_format: 'xml',
              source_specific_fields: {
                'eu:logicalId' => entity.logical_id,
                'eu:unitedNationId' => entity.united_nation_id,
                'eu:designationDetails' => entity.designation_details,
                'eu:subjectTypeCode' => entity.subject_type&.code
              }
            )
          )
        end

        # Transform EU name aliases to NameVariant objects
        # @param name_aliases [Array<Ammitto::Sources::Eu::NameAlias>]
        # @return [Array<NameVariant>]
        def transform_names(name_aliases)
          name_aliases.map.with_index do |name, idx|
            create_name_variant(
              full_name: name.whole_name,
              first_name: name.first_name,
              middle_name: name.middle_name,
              last_name: name.last_name,
              script: detect_script(name.whole_name),
              is_primary: idx.zero?
            )
          end
        end

        # Transform EU addresses to Address objects
        # @param addresses [Array<Ammitto::Sources::Eu::Address>]
        # @return [Array<Address>]
        def transform_addresses(addresses)
          addresses.map do |addr|
            create_address(
              street: addr.street,
              city: addr.city,
              state: addr.region,
              country: addr.country_description,
              country_iso_code: addr.country_iso2_code,
              postal_code: addr.zip_code
            )
          end
        end

        # Transform EU birthdates to BirthInfo objects
        # @param birthdates [Array<Ammitto::Sources::Eu::Birthdate>]
        # @return [Array<BirthInfo>]
        def transform_birthdates(birthdates)
          birthdates.map do |bd|
            date = parse_eu_date(bd.birthdate) || parse_year(bd.year)

            create_birth_info(
              date: date,
              circa: bd.circa,
              city: [bd.city, bd.place].compact.first,
              region: bd.region,
              country: bd.country_description,
              country_iso_code: bd.country_iso2_code
            )
          end
        end

        # Transform EU identifications to Identification objects
        # @param identifications [Array<Ammitto::Sources::Eu::Identification>]
        # @return [Array<Identification>]
        def transform_identifications(identifications)
          identifications.map do |id|
            create_identification(
              type: normalize_id_type(id.identification_type_code),
              number: id.number,
              issuing_country: id.country_iso2_code
            )
          end
        end

        # Transform EU regulations to LegalInstrument objects
        # @param regulations [Array<Ammitto::Sources::Eu::Regulation>]
        # @return [Array<LegalInstrument>]
        def transform_regulations(regulations)
          regulations.map do |reg|
            Ammitto::LegalInstrument.new(
              type: normalize_instrument_type(reg.regulation_type),
              identifier: reg.number_title,
              title: reg.number_title,
              issuing_body: reg.organisation_type&.capitalize,
              issuance_date: parse_date(reg.publication_date),
              url: reg.publication_url
            )
          end
        end

        # Transform EU programme code to SanctionRegime
        # @param programme [String, nil]
        # @return [SanctionRegime]
        def transform_regime(programme)
          return create_regime(code: 'UNKNOWN', name: 'Unknown') if programme.nil?

          info = REGIME_MAPPING[programme.upcase] || { code: programme.upcase, name: programme }

          create_regime(code: info[:code], name: info[:name])
        end

        # Create default effects for EU sanctions
        # EU sanctions typically include asset freeze and sometimes travel ban
        # @return [Array<SanctionEffect>]
        def create_default_effects
          [
            create_effect(effect_type: 'asset_freeze', scope: 'full')
          ]
        end

        # Parse EU date format (YYYY-MM-DD)
        # @param date_str [String, nil]
        # @return [Date, nil]
        def parse_eu_date(date_str)
          return nil if date_str.nil? || date_str.empty?

          parse_date(date_str)
        end

        # Parse year-only value
        # @param year [Integer, String, nil]
        # @return [Date, nil]
        def parse_year(year)
          return nil if year.nil?

          year_int = year.is_a?(Integer) ? year : year.to_i
          return nil if year_int.zero?

          Date.new(year_int, 1, 1)
        rescue Date::Error
          nil
        end

        # Normalize identification type code
        # @param code [String, nil]
        # @return [String]
        def normalize_id_type(code)
          return 'Other' if code.nil?

          case code.downcase
          when 'passport'
            'Passport'
          when 'national_id', 'nationalid'
            'NationalID'
          when 'tax_id', 'taxid'
            'TaxID'
          when 'drivers_license', 'driver_license'
            'DriversLicense'
          when 'diplomatic_passport'
            'DiplomaticPassport'
          else
            code.split('_').map(&:capitalize).join
          end
        end

        # Normalize instrument type
        # @param type [String, nil]
        # @return [String]
        def normalize_instrument_type(type)
          return 'regulation' if type.nil?

          case type.downcase
          when 'regulation'
            'regulation'
          when 'decision'
            'decision'
          when 'directive'
            'directive'
          else
            type.downcase
          end
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
Ammitto::Transformers::EuTransformer = Ammitto::Sources::Eu::Transformer
