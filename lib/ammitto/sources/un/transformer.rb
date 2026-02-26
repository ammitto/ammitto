# frozen_string_literal: true

require_relative '../../transformers/base_transformer'

module Ammitto
  module Sources
    module Un
      # Transformer converts UN source models to the harmonized
      # Ammitto ontology models.
      #
      # @example Transforming a UN individual
      #   transformer = Ammitto::Sources::Un::Transformer.new
      #   result = transformer.transform_individual(individual)
      #   entity = result[:entity]    # PersonEntity
      #   entry = result[:entry]      # SanctionEntry
      #
      class Transformer < Ammitto::Transformers::BaseTransformer
        # Mapping of UN list types to regime codes
        REGIME_MAPPING = {
          'DRC' => { code: 'DRC', name: 'Democratic Republic of the Congo' },
          'DPRK' => { code: 'DPRK', name: "Democratic People's Republic of Korea" },
          'IRAN' => { code: 'IRAN', name: 'Iran' },
          'IRAQ' => { code: 'IRAQ', name: 'Iraq' },
          'LIBYA' => { code: 'LIBYA', name: 'Libya' },
          'SOMALIA' => { code: 'SOMALIA', name: 'Somalia' },
          'SUDAN' => { code: 'SUDAN', name: 'Sudan' },
          'TAHBAN' => { code: 'TALIBAN', name: 'Taliban' },
          'AL-QAIDA' => { code: 'AL-QAIDA', name: 'Al-Qaida' },
          "COTE_D'IVOIRE" => { code: 'COTE_DIVOIRE', name: "Cote d'Ivoire" },
          'LIBERIA' => { code: 'LIBERIA', name: 'Liberia' },
          'GUINEA-BISSAU' => { code: 'GUINEA_BISSAU', name: 'Guinea-Bissau' },
          'CENTRAL_AFRICAN_REPUBLIC' => { code: 'CAR', name: 'Central African Republic' },
          'YEMEN' => { code: 'YEMEN', name: 'Yemen' },
          'SOUTH_SUDAN' => { code: 'SOUTH_SUDAN', name: 'South Sudan' },
          'MALI' => { code: 'MALI', name: 'Mali' },
          'CAR' => { code: 'CAR', name: 'Central African Republic' }
        }.freeze

        def initialize
          super(:un)
        end

        # Transform a UN Individual to ontology models
        # @param individual [Ammitto::Sources::Un::Individual] the UN individual
        # @return [Hash] { entity: PersonEntity, entry: SanctionEntry }
        def transform_individual(individual)
          entity = create_person_entity(individual)
          entry = create_entry_from_individual(individual)

          # Link entity to entry
          entity.add_sanction_entry(entry)

          {
            entity: entity,
            entry: entry
          }
        end

        # Transform a UN Entity (organization) to ontology models
        # @param entity [Ammitto::Sources::Un::Entity] the UN entity
        # @return [Hash] { entity: OrganizationEntity, entry: SanctionEntry }
        def transform_entity(entity)
          ont_entity = create_organization_entity(entity)
          entry = create_entry_from_entity(entity)

          # Link entity to entry
          ont_entity.add_sanction_entry(entry)

          {
            entity: ont_entity,
            entry: entry
          }
        end

        # Generic transform method - detects type and delegates
        # @param source [Object] UN Individual or Entity
        # @return [Hash] { entity: Entity, entry: SanctionEntry }
        def transform(source)
          case source
          when Ammitto::Sources::Un::Individual
            transform_individual(source)
          when Ammitto::Sources::Un::Entity
            transform_entity(source)
          else
            raise ArgumentError, "Unknown source type: #{source.class}"
          end
        end

        private

        # Create a PersonEntity from a UN Individual
        # @param individual [Ammitto::Sources::Un::Individual]
        # @return [PersonEntity]
        def create_person_entity(individual)
          Ammitto::PersonEntity.new(
            id: generate_entity_id(individual.reference_number),
            entity_type: 'person',
            names: transform_individual_names(individual),
            addresses: transform_individual_addresses(individual.addresses),
            birth_info: transform_birth_info(individual),
            nationalities: individual.nationality_values,
            gender: individual.gender,
            identifications: transform_documents(individual.documents),
            title: extract_title(individual.designation_values),
            position: individual.designation_values.first,
            remarks: individual.comments1
          )
        end

        # Create an OrganizationEntity from a UN Entity
        # @param entity [Ammitto::Sources::Un::Entity]
        # @return [OrganizationEntity]
        def create_organization_entity(entity)
          Ammitto::OrganizationEntity.new(
            id: generate_entity_id(entity.reference_number),
            entity_type: 'organization',
            names: transform_entity_names(entity),
            addresses: transform_entity_addresses(entity.addresses),
            remarks: entity.comments1
          )
        end

        # Create a SanctionEntry from a UN Individual
        # @param individual [Ammitto::Sources::Un::Individual]
        # @return [SanctionEntry]
        def create_entry_from_individual(individual)
          create_sanction_entry(
            reference_number: individual.reference_number,
            regime_code: individual.un_list_type,
            listed_on: individual.listed_on,
            last_updated: individual.last_day_updated&.value,
            remarks: individual.comments1,
            source_specific_fields: {
              'un:dataId' => individual.dataid,
              'un:versionNum' => individual.versionnum,
              'un:gender' => individual.gender,
              'un:entityType' => 'individual'
            }
          )
        end

        # Create a SanctionEntry from a UN Entity
        # @param entity [Ammitto::Sources::Un::Entity]
        # @return [SanctionEntry]
        def create_entry_from_entity(entity)
          create_sanction_entry(
            reference_number: entity.reference_number,
            regime_code: entity.un_list_type,
            listed_on: entity.listed_on,
            last_updated: entity.last_day_updated&.value,
            remarks: entity.comments1,
            source_specific_fields: {
              'un:dataId' => entity.dataid,
              'un:versionNum' => entity.versionnum,
              'un:entityType' => 'entity'
            }
          )
        end

        # Create a SanctionEntry with common fields
        # @return [SanctionEntry]
        def create_sanction_entry(reference_number:, regime_code:, listed_on:,
                                  last_updated:, remarks:, source_specific_fields:)
          Ammitto::SanctionEntry.new(
            id: generate_entry_id(reference_number),
            entity_id: generate_entity_id(reference_number),
            authority: authority,
            regime: transform_regime(regime_code),
            effects: create_default_effects,
            period: create_period(
              listed_date: listed_on,
              effective_date: listed_on,
              last_updated: last_updated
            ),
            status: 'active',
            reference_number: reference_number,
            remarks: remarks,
            raw_source_data: create_raw_source_data(
              source_format: 'xml',
              source_specific_fields: source_specific_fields
            )
          )
        end

        # Transform UN individual names to NameVariant objects
        # @param individual [Ammitto::Sources::Un::Individual]
        # @return [Array<NameVariant>]
        def transform_individual_names(individual)
          names = []

          # Primary name from individual name parts
          full_name = individual.full_name
          if full_name && !full_name.empty?
            middle_name_parts = [individual.second_name, individual.third_name].compact
            middle_name = middle_name_parts.empty? ? nil : middle_name_parts.join(' ')

            names << create_name_variant(
              full_name: full_name,
              first_name: individual.first_name,
              middle_name: middle_name,
              last_name: individual.fourth_name,
              is_primary: true,
              script: 'Latn'
            )
          end

          # Aliases
          if individual.aliases
            individual.aliases.each do |alias_obj|
              names << create_name_variant(
                full_name: alias_obj.alias_name,
                is_primary: false,
                script: detect_script(alias_obj.alias_name)
              )
            end
          end

          names
        end

        # Transform UN entity names to NameVariant objects
        # @param entity [Ammitto::Sources::Un::Entity]
        # @return [Array<NameVariant>]
        def transform_entity_names(entity)
          names = []

          # Primary name
          if entity.first_name
            names << create_name_variant(
              full_name: entity.first_name,
              is_primary: true,
              script: 'Latn'
            )
          end

          # Aliases
          if entity.aliases
            entity.aliases.each do |alias_obj|
              names << create_name_variant(
                full_name: alias_obj.alias_name,
                is_primary: false,
                script: detect_script(alias_obj.alias_name)
              )
            end
          end

          names
        end

        # Transform UN individual addresses to Address objects
        # @param addresses [Array<Ammitto::Sources::Un::IndividualAddress>, nil]
        # @return [Array<Address>]
        def transform_individual_addresses(addresses)
          return [] if addresses.nil?

          addresses.map do |addr|
            create_address(
              street: addr.street,
              city: addr.city,
              state: addr.state_province,
              country: addr.country
            )
          end
        end

        # Transform UN entity addresses to Address objects
        # @param addresses [Array<Ammitto::Sources::Un::EntityAddress>, nil]
        # @return [Array<Address>]
        def transform_entity_addresses(addresses)
          return [] if addresses.nil?

          addresses.map do |addr|
            create_address(
              street: addr.street,
              city: addr.city,
              state: addr.state_province,
              country: addr.country
            )
          end
        end

        # Transform UN birth info to BirthInfo objects
        # @param individual [Ammitto::Sources::Un::Individual]
        # @return [Array<BirthInfo>]
        def transform_birth_info(individual)
          birth_infos = []

          dob = individual.date_of_birth
          pob = individual.place_of_birth

          if dob
            date = parse_un_date(dob)
            birth_infos << create_birth_info(
              date: date,
              circa: dob.type_of_date&.include?('APPROXIMATELY'),
              city: pob&.city,
              region: pob&.state_province,
              country: pob&.country
            )
          elsif pob
            # No DOB but has POB
            birth_infos << create_birth_info(
              city: pob.city,
              region: pob.state_province,
              country: pob.country
            )
          end

          birth_infos
        end

        # Transform UN documents to Identification objects
        # @param documents [Array<Ammitto::Sources::Un::IndividualDocument>, nil]
        # @return [Array<Identification>]
        def transform_documents(documents)
          return [] if documents.nil?

          documents.map do |doc|
            create_identification(
              type: normalize_doc_type(doc.type_of_document),
              number: doc.number,
              issuing_country: doc.issuing_country,
              note: doc.note
            )
          end
        end

        # Transform UN list type to SanctionRegime
        # @param list_type [String, nil]
        # @return [SanctionRegime]
        def transform_regime(list_type)
          return create_regime(code: 'UNKNOWN', name: 'Unknown') if list_type.nil?

          # Normalize list type (convert hyphens to underscores for lookup)
          normalized = list_type.upcase.gsub('-', '_')

          info = REGIME_MAPPING[normalized] || { code: normalized, name: list_type }

          create_regime(code: info[:code], name: info[:name])
        end

        # Create default effects for UN sanctions
        # UN sanctions typically include asset freeze and travel ban
        # @return [Array<SanctionEffect>]
        def create_default_effects
          [
            create_effect(effect_type: 'asset_freeze', scope: 'full'),
            create_effect(effect_type: 'travel_ban', scope: 'full')
          ]
        end

        # Parse UN date format
        # @param dob [Ammitto::Sources::Un::IndividualDateOfBirth]
        # @return [Date, nil]
        def parse_un_date(dob)
          return nil unless dob

          if dob.date && !dob.date.empty?
            parse_date(dob.date)
          elsif dob.year
            begin
              Date.new(dob.year, 1, 1)
            rescue Date::Error
              nil
            end
          end
        end

        # Extract title from designations
        # @param designations [Array<String>]
        # @return [String, nil]
        def extract_title(designations)
          return nil if designations.nil? || designations.empty?

          # Look for common title patterns
          designations.find do |d|
            d&.match?(/^(General|Colonel|Minister|Director|President|Admiral|Commander)/i)
          end
        end

        # Normalize document type
        # @param type [String, nil]
        # @return [String]
        def normalize_doc_type(type)
          return 'Other' if type.nil?

          case type.downcase
          when /passport/
            'Passport'
          when /national.*id/, /identity/
            'NationalID'
          when /driver/
            'DriversLicense'
          when /diplomatic/
            'DiplomaticPassport'
          else
            type.split.map(&:capitalize).join(' ')
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
Ammitto::Transformers::UnTransformer = Ammitto::Sources::Un::Transformer
