# frozen_string_literal: true

require_relative '../../transformers/base_transformer'
require_relative '../../utils/presence'

module Ammitto
  module Sources
    module Us
      # Transformer converts US OFAC SDN source models to the harmonized
      # Ammitto ontology models.
      #
      # @example Transforming a US SDN entry
      #   transformer = Ammitto::Sources::Us::Transformer.new
      #   result = transformer.transform(sdn_entry)
      #   entity = result[:entity]    # PersonEntity, OrganizationEntity, VesselEntity, or AircraftEntity
      #   entry = result[:entry]      # SanctionEntry
      #
      class Transformer < Ammitto::Transformers::BaseTransformer
        # Mapping of OFAC program codes to regime info
        REGIME_MAPPING = {
          'SDGT' => { code: 'SDGT', name: 'Specially Designated Global Terrorist' },
          'SDT' => { code: 'SDT', name: 'Specially Designated Terrorist' },
          'SDTK' => { code: 'SDTK', name: 'Specially Designated Terrorist (Taliban)' },
          'FSE' => { code: 'FSE', name: 'Foreign Sanctions Evaders' },
          'NS-PLC' => { code: 'NS_PLC', name: 'Palestinian Legislative Council' },
          'SDNR' => { code: 'SDNR', name: 'Specially Designated Nationals (Russia)' },
          'UKRAINE-EO13662' => { code: 'RUSSIA', name: 'Russia/Ukraine' },
          'RUSSIA-EO14024' => { code: 'RUSSIA', name: 'Russia/Ukraine' },
          'RUSSIA-EO14038' => { code: 'RUSSIA', name: 'Russia/Ukraine' },
          'RUSSIA-EO14068' => { code: 'RUSSIA', name: 'Russia/Ukraine' },
          'RUSSIA-EO14071' => { code: 'RUSSIA', name: 'Russia/Ukraine' },
          'CYBER2' => { code: 'CYBER', name: 'Cyber-Related Sanctions' },
          'CYBER3' => { code: 'CYBER', name: 'Cyber-Related Sanctions' },
          'IRAN' => { code: 'IRAN', name: 'Iran' },
          'IRGC' => { code: 'IRAN', name: 'Iran (IRGC)' },
          'DPRK' => { code: 'DPRK', name: "Democratic People's Republic of Korea" },
          'DPRK2' => { code: 'DPRK', name: "Democratic People's Republic of Korea" },
          'DPRK3' => { code: 'DPRK', name: "Democratic People's Republic of Korea" },
          'DPRK4' => { code: 'DPRK', name: "Democratic People's Republic of Korea" },
          'CUBA' => { code: 'CUBA', name: 'Cuba' },
          'CUBA2' => { code: 'CUBA', name: 'Cuba' },
          'CUBA3' => { code: 'CUBA', name: 'Cuba' },
          'CUBA4' => { code: 'CUBA', name: 'Cuba' },
          'CUBA5' => { code: 'CUBA', name: 'Cuba' },
          'SYRIA' => { code: 'SYRIA', name: 'Syria' },
          'VENEZUELA' => { code: 'VENEZUELA', name: 'Venezuela' },
          'BURMA' => { code: 'MYANMAR', name: 'Myanmar' },
          'BELARUS' => { code: 'BELARUS', name: 'Belarus' },
          'ZIMBABWE' => { code: 'ZIMBABWE', name: 'Zimbabwe' },
          'SUDAN' => { code: 'SUDAN', name: 'Sudan' },
          'SOMALIA' => { code: 'SOMALIA', name: 'Somalia' },
          'LIBYA' => { code: 'LIBYA', name: 'Libya' },
          'YEMEN' => { code: 'YEMEN', name: 'Yemen' },
          'IRQ' => { code: 'IRAQ', name: 'Iraq' },
          'IRAQ2' => { code: 'IRAQ', name: 'Iraq' },
          'LEBANON' => { code: 'LEBANON', name: 'Lebanon' },
          'HRIT-EO13818' => { code: 'HRIT', name: 'Human Rights' },
          'CMIC-EO13959' => { code: 'CMIC', name: 'Chinese Military-Industrial Complex' },
          'CMIC-EO14032' => { code: 'CMIC', name: 'Chinese Military-Industrial Complex' },
          'CAATSA' => { code: 'CAATSA', name: 'CAATSA' }
        }.freeze

        def initialize
          super(:us)
        end

        # Transform a US SDN Entry to ontology models
        # @param sdn_entry [Ammitto::Sources::Us::SdnEntry] the SDN entry
        # @return [Hash] { entity: Entity, entry: SanctionEntry }
        def transform(sdn_entry)
          @current_sdn = sdn_entry

          entity = create_entity(sdn_entry)
          entry = create_entry(sdn_entry)

          # Link entity to entry
          link_entry(entity, entry)

          {
            entity: entity,
            entry: entry
          }
        ensure
          @current_sdn = nil
        end
        canonical_entrypoints :transform

        private

        # Create the appropriate entity type based on SDN type
        # @param sdn_entry [Ammitto::Sources::Us::SdnEntry]
        # @return [PersonEntity, OrganizationEntity, VesselEntity, AircraftEntity]
        def create_entity(sdn_entry)
          case sdn_entry.entity_type
          when 'person'
            create_person_entity(sdn_entry)
          when 'vessel'
            create_vessel_entity(sdn_entry)
          when 'aircraft'
            create_aircraft_entity(sdn_entry)
          else
            create_organization_entity(sdn_entry)
          end
        end

        # Create a PersonEntity from an SDN entry
        # @param sdn_entry [Ammitto::Sources::Us::SdnEntry]
        # @return [PersonEntity]
        def create_person_entity(sdn_entry)
          build_model(Ammitto::PersonEntity,
                      id: generate_entity_id(sdn_entry.uid),
                      entity_type: 'person',
                      names: transform_sdn_names(sdn_entry),
                      addresses: transform_addresses(sdn_entry.addresses),
                      birth_info: transform_birth_info(sdn_entry),
                      identifications: transform_identifications(sdn_entry.identifications),
                      title: sdn_entry.title,
                      nationalities: (sdn_entry.nationalities + sdn_entry.citizenships).uniq,
                      remarks: sdn_entry.remarks)
        end

        # Create an OrganizationEntity from an SDN entry
        # @param sdn_entry [Ammitto::Sources::Us::SdnEntry]
        # @return [OrganizationEntity]
        def create_organization_entity(sdn_entry)
          build_model(Ammitto::OrganizationEntity,
                      id: generate_entity_id(sdn_entry.uid),
                      entity_type: 'organization',
                      names: transform_sdn_names(sdn_entry),
                      addresses: transform_addresses(sdn_entry.addresses),
                      remarks: sdn_entry.remarks)
        end

        # Create a VesselEntity from an SDN entry
        # @param sdn_entry [Ammitto::Sources::Us::SdnEntry]
        # @return [VesselEntity]
        def create_vessel_entity(sdn_entry)
          # Extract vessel-specific data from identifications
          vessel_ids = sdn_entry.identifications.select { |id| vessel_id_type?(id.id_type) }
          imo = vessel_ids.find { |id| id.id_type&.downcase&.include?('imo') }
          info = sdn_entry.vessel_info
          flag = Ammitto::Utils::Presence.presence(info&.vessel_flag) ||
                 extract_flag_from_addresses(sdn_entry.addresses)

          build_model(Ammitto::VesselEntity,
                      id: generate_entity_id(sdn_entry.uid),
                      entity_type: 'vessel',
                      names: transform_sdn_names(sdn_entry),
                      imo_number: imo&.id_number,
                      flag_state: flag,
                      vessel_type: Ammitto::Utils::Presence.presence(info&.vessel_type),
                      call_sign: Ammitto::Utils::Presence.presence(info&.call_sign),
                      tonnage: transform_tonnage(info),
                      owner: transform_vessel_owner(info),
                      remarks: sdn_entry.remarks)
        end

        # OFAC's grossRegisteredTonnage is the only tonnage element that
        # names its measure. The bare <tonnage> element does not, so it is
        # kept in raw_source_data instead of being filed under a measure
        # the source never stated.
        # @param info [Ammitto::Sources::Us::VesselInfo, nil]
        # @return [Tonnage, nil]
        def transform_tonnage(info)
          grt = parse_tonnage(info&.gross_registered_tonnage)
          return nil unless grt

          build_model(Ammitto::Tonnage, gross_register_tonnage: grt)
        end

        # @param value [String, nil]
        # @return [Integer, nil] nil when absent or not a plain integer
        def parse_tonnage(value)
          value.to_s.strip.match?(/\A\d+\z/) ? value.to_i : nil
        end

        # @param info [Ammitto::Sources::Us::VesselInfo, nil]
        # @return [EntityLink, nil] a named owner; OFAC gives no entity to link
        def transform_vessel_owner(info)
          name = Ammitto::Utils::Presence.presence(info&.vessel_owner)
          name && build_model(Ammitto::EntityLink, relationship: 'owned_by', target_name: name)
        end

        # Create an AircraftEntity from an SDN entry
        # @param sdn_entry [Ammitto::Sources::Us::SdnEntry]
        # @return [AircraftEntity]
        def create_aircraft_entity(sdn_entry)
          # Extract aircraft-specific data from identifications
          aircraft_ids = sdn_entry.identifications.select { |id| aircraft_id_type?(id.id_type) }
          reg = aircraft_ids.find { |id| id.id_type&.downcase&.include?('registration') }
          flag = extract_flag_from_addresses(sdn_entry.addresses)

          build_model(Ammitto::AircraftEntity,
                      id: generate_entity_id(sdn_entry.uid),
                      entity_type: 'aircraft',
                      names: transform_sdn_names(sdn_entry),
                      registration_number: reg&.id_number,
                      flag_state: flag,
                      remarks: sdn_entry.remarks)
        end

        # Create a SanctionEntry from an SDN entry
        # @param sdn_entry [Ammitto::Sources::Us::SdnEntry]
        # @return [SanctionEntry]
        def create_entry(sdn_entry)
          programs = sdn_entry.programs
          primary_regime = programs.first

          build_model(Ammitto::SanctionEntry,
                      id: generate_entry_id(sdn_entry.uid),
                      entity_id: generate_entity_id(sdn_entry.uid),
                      authority: authority,
                      regime: transform_regime(primary_regime),
                      effects: create_default_effects,
                      status: 'active',
                      reference_number: sdn_entry.uid,
                      remarks: sdn_entry.remarks,
                      raw_source_data: create_raw_source_data(
                        source_format: 'xml',
                        source_specific_fields: {
                          'us:sdnType' => sdn_entry.sdn_type,
                          'us:programs' => programs,
                          'us:title' => sdn_entry.title
                        }.merge(unpublished_fields(sdn_entry))
                      ))
        end

        # Source values with no ontology field of their own. Nationality and
        # citizenship are published together as PersonEntity#nationalities;
        # keeping them apart here preserves which one the source stated.
        # @param sdn_entry [Ammitto::Sources::Us::SdnEntry]
        # @return [Hash{String => Object}]
        def unpublished_fields(sdn_entry)
          info = sdn_entry.vessel_info
          {
            'us:nationalities' => sdn_entry.nationalities,
            'us:citizenships' => sdn_entry.citizenships,
            'us:vesselTonnage' => info&.tonnage,
            'us:vesselGrossRegisteredTonnage' => unparsed_tonnage(info)
          }.reject { |_, value| value.nil? || value == [] || value.to_s.strip.empty? }
        end

        # A grossRegisteredTonnage that is not a plain integer cannot be
        # published as a number; the stated text survives here instead.
        # @param info [Ammitto::Sources::Us::VesselInfo, nil]
        # @return [String, nil]
        def unparsed_tonnage(info)
          value = info&.gross_registered_tonnage
          value if value && parse_tonnage(value).nil?
        end

        # Transform SDN names to NameVariant objects
        # @param sdn_entry [Ammitto::Sources::Us::SdnEntry]
        # @return [Array<NameVariant>]
        def transform_sdn_names(sdn_entry)
          names = []

          # Primary name
          primary = sdn_entry.primary_name
          if primary && !primary.empty?
            names << create_name_variant(
              full_name: primary,
              first_name: sdn_entry.first_name,
              last_name: sdn_entry.last_name,
              is_primary: true,
              script: 'Latn'
            )
          end

          # Aliases (AKA)
          sdn_entry.aliases.each do |aka|
            full_name = aka.full_name
            next if full_name.nil? || full_name.empty?

            names << create_name_variant(
              full_name: full_name,
              first_name: aka.first_name,
              last_name: aka.last_name,
              is_primary: false,
              script: detect_script(full_name)
            )
          end

          names
        end

        # Transform US addresses to Address objects
        # @param addresses [Array<Ammitto::Sources::Us::Address>]
        # @return [Array<Address>]
        def transform_addresses(addresses)
          addresses.map do |addr|
            street = [addr.address1, addr.address2, addr.address3].compact.reject(&:empty?).join(', ')

            create_address(
              street: street,
              city: addr.city,
              state: addr.state_or_province,
              country: addr.country,
              postal_code: addr.postal_code
            )
          end
        end

        # Transform SDN birth info to BirthInfo objects
        # @param sdn_entry [Ammitto::Sources::Us::SdnEntry]
        # @return [Array<BirthInfo>]
        def transform_birth_info(sdn_entry)
          birth_infos = []

          # Combine DOB and POB data
          dobs = sdn_entry.dates_of_birth
          pobs = sdn_entry.places_of_birth

          dobs.each_with_index do |dob, idx|
            pob = pobs[idx]

            # OFAC DOBs mix complete dates ("03 Oct 1988") with partial
            # ones ("1988", "Oct 1988", "circa 1960") and with spans
            # ("01 Jan 1961 to 31 Dec 1962"). The whole string is
            # forwarded untouched: reading it is create_birth_info's
            # job, not this transformer's. Only a complete date becomes
            # BirthInfo#date; a partial value's stated year survives in
            # BirthInfo#year; a span becomes bounds instead, and only a
            # span whose endpoints share a year still states a scalar
            # one.
            birth_infos << create_birth_info(
              date: dob.date_of_birth,
              circa: circa_string?(dob.date_of_birth),
              city: pob&.place_of_birth
            )
          end

          # If no DOB but has POB
          if birth_infos.empty? && pobs.any?
            pobs.each do |pob|
              birth_infos << create_birth_info(
                city: pob.place_of_birth
              )
            end
          end

          birth_infos
        end

        # Transform US identifications to Identification objects
        # @param identifications [Array<Ammitto::Sources::Us::Id>]
        # @return [Array<Identification>]
        def transform_identifications(identifications)
          identifications.map do |id|
            create_identification(
              type: normalize_id_type(id.id_type),
              number: id.id_number,
              issuing_country: id.id_country,
              note: build_id_note(id)
            )
          end
        end

        # Transform OFAC program to SanctionRegime
        # @param program [String, nil]
        # @return [SanctionRegime]
        def transform_regime(program)
          return create_regime(code: 'SDN', name: 'Specially Designated Nationals') if program.nil?

          info = REGIME_MAPPING[program.upcase] || { code: program.upcase, name: program }

          create_regime(code: info[:code], name: info[:name])
        end

        # Create default effects for US sanctions
        # US SDN sanctions typically include asset freeze
        # @return [Array<SanctionEffect>]
        def create_default_effects
          [
            create_effect(effect_type: 'asset_freeze', scope: 'full')
          ]
        end

        # Check if ID type is vessel-related
        # @param type [String, nil]
        # @return [Boolean]
        def vessel_id_type?(type)
          return false if type.nil?

          type.downcase.match?(/imo|vessel|tonnage|flag|build/)
        end

        # Check if ID type is aircraft-related
        # @param type [String, nil]
        # @return [Boolean]
        def aircraft_id_type?(type)
          return false if type.nil?

          type.downcase.match?(/registration|serial|aircraft|manufacturer/)
        end

        # Extract flag state from addresses
        # @param addresses [Array<Ammitto::Sources::Us::Address>]
        # @return [String, nil]
        def extract_flag_from_addresses(addresses)
          addresses.first&.country
        end

        # Normalize ID type
        # @param type [String, nil]
        # @return [String]
        def normalize_id_type(type)
          return 'Other' if type.nil?

          case type.downcase
          when /passport/
            'Passport'
          when /national.*id/, /cuit/, /curp/, /rfc/, /dni/, /ce/
            'NationalID'
          when /tax/, /taxpayer/, /ein/, /ssn/, /itin/
            'TaxID'
          when /driver/
            'DriversLicense'
          when /imo/, /vessel.*id/
            'VesselID'
          when /registration/, /tail.*number/
            'AircraftRegistration'
          when /seafarer/
            'SeafarerID'
          when /diplomatic/
            'DiplomaticPassport'
          when /military/
            'MilitaryID'
          else
            type.split.map(&:capitalize).join(' ')
          end
        end

        # Build ID note from issue/expiry dates
        # @param id [Ammitto::Sources::Us::Id]
        # @return [String, nil]
        def build_id_note(id)
          parts = []
          parts << "Issued: #{id.issue_date}" if id.issue_date && !id.issue_date.empty?
          parts << "Expires: #{id.expiration_date}" if id.expiration_date && !id.expiration_date.empty?
          result = parts.join('; ')
          result.empty? ? nil : result
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
Ammitto::Transformers::UsTransformer = Ammitto::Sources::Us::Transformer
