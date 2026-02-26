# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require 'json'

module Ammitto
  module Exporter
    # Export raw YAML data to JSON-LD format
    #
    # Reads from eu-data/, un-data/, etc. and outputs to data/
    class JsonLdExport
      SOURCE_DIRS = {
        eu: 'eu-data',
        un: 'un-data',
        us: 'us-govt-data',
        wb: 'wb-data',
        gb: 'gb-data',
        au: 'au-data',
        ca: 'ca-data',
        ch: 'ch-data',
        cn: 'cn-data',
        ru: 'ru-data'
      }.freeze

      attr_reader :base_dir, :output_dir, :serializer

      def initialize(base_dir: nil, output_dir: nil)
        @base_dir = base_dir || default_base_dir
        @output_dir = output_dir || File.join(@base_dir, 'data')
        @serializer = Ammitto::Serialization::JsonLdSerializer.new
      end

      # Export all sources to JSON-LD
      #
      # @return [Hash] summary of exported data
      def export_all
        results = {}
        all_entities = []
        all_entries = []

        SOURCE_DIRS.each_key do |code|
          result = export_source(code)
          results[code] = result
          all_entities.concat(result[:entities]) if result[:entities]
          all_entries.concat(result[:entries]) if result[:entries]
        end

        # Create combined file
        export_combined(all_entities, all_entries)

        results[:total] = {
          entities: all_entities.length,
          entries: all_entries.length
        }

        results
      end

      # Export a single source to JSON-LD
      #
      # @param source_code [Symbol] the source code (e.g., :eu, :un)
      # @return [Hash] summary of exported data
      def export_source(source_code)
        dir = SOURCE_DIRS[source_code]
        raise ArgumentError, "Unknown source: #{source_code}" unless dir

        source_dir = File.join(base_dir, dir, 'processed')
        return { error: "Directory not found: #{source_dir}" } unless Dir.exist?(source_dir)

        entities = []
        entries = []

        # Process all YAML files
        yaml_files = Dir.glob(File.join(source_dir, '*.yaml'))
        yaml_files.each do |yaml_file|
          entity_data = load_yaml(yaml_file)
          next unless entity_data

          entity = build_entity(entity_data, source_code)
          entities << entity if entity

          entry = build_entry(entity_data, source_code, entity)
          entries << entry if entry
        end

        # Export source JSON-LD file
        export_source_file(source_code, entities, entries)

        {
          source: source_code,
          files_processed: yaml_files.length,
          entities: entities,
          entries: entries
        }
      end

      private

      def default_base_dir
        # Find the parent directory of the ammitto gem
        File.expand_path('../../../..', __dir__)
      end

      def load_yaml(file_path)
        YAML.safe_load_file(file_path, permitted_classes: [Date, Time])
      rescue StandardError => e
        Logger.warn("Failed to load #{file_path}: #{e.message}")
        nil
      end

      def build_entity(data, source_code)
        entity_type = data['entity_type'] || 'organization'

        case entity_type
        when 'person'
          build_person_entity(data, source_code)
        when 'organization'
          build_organization_entity(data, source_code)
        when 'vessel'
          build_vessel_entity(data, source_code)
        when 'aircraft'
          build_aircraft_entity(data, source_code)
        else
          build_organization_entity(data, source_code)
        end
      end

      def build_person_entity(data, source_code)
        Ammitto::PersonEntity.new(
          id: generate_entity_id(data, source_code),
          entity_type: 'person',
          names: build_names(data['names']),
          birth_info: build_birth_info(data),
          nationalities: [data['country']].compact,
          addresses: build_addresses(data['address']),
          identifications: build_identifications(data),
          source_references: [build_source_reference(data, source_code)]
        )
      end

      def build_organization_entity(data, source_code)
        Ammitto::OrganizationEntity.new(
          id: generate_entity_id(data, source_code),
          entity_type: 'organization',
          names: build_names(data['names']),
          country: data['country'],
          addresses: build_addresses(data['address']),
          source_references: [build_source_reference(data, source_code)]
        )
      end

      def build_vessel_entity(data, source_code)
        Ammitto::VesselEntity.new(
          id: generate_entity_id(data, source_code),
          entity_type: 'vessel',
          names: build_names(data['names']),
          flag_state: data['country'],
          source_references: [build_source_reference(data, source_code)]
        )
      end

      def build_aircraft_entity(data, source_code)
        Ammitto::AircraftEntity.new(
          id: generate_entity_id(data, source_code),
          entity_type: 'aircraft',
          names: build_names(data['names']),
          flag_state: data['country'],
          source_references: [build_source_reference(data, source_code)]
        )
      end

      def build_entry(data, source_code, entity)
        return nil unless entity

        Ammitto::SanctionEntry.new(
          id: generate_entry_id(data, source_code),
          entity_id: entity.id,
          authority: build_authority(source_code),
          regime: build_regime(data, source_code),
          legal_bases: build_legal_bases(data, source_code),
          effects: build_effects(data, entity),
          status: map_status(data['status']),
          reference_number: data['ref_number'],
          remarks: data['remark'],
          period: build_period(data),
          raw_source_data: build_raw_data(data, source_code)
        )
      end

      def generate_entity_id(data, source_code)
        ref = data['ref_number'] || data['names']&.first || 'unknown'
        slug = ref.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')
        "https://ammitto.org/entity/#{source_code}/#{slug}"
      end

      def generate_entry_id(data, source_code)
        ref = data['ref_number'] || data['names']&.first || 'unknown'
        slug = ref.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')
        "https://ammitto.org/entry/#{source_code}/#{slug}"
      end

      def build_names(names_array)
        return [] unless names_array.is_a?(Array)

        names_array.map do |name|
          Ammitto::NameVariant.new(
            full_name: name.to_s,
            is_primary: name == names_array.first
          )
        end
      end

      def build_birth_info(data)
        return [] unless data['birthdate']

        [Ammitto::BirthInfo.new(
          date: data['birthdate'],
          country: data['country']
        )]
      end

      def build_addresses(address_data)
        return [] unless address_data.is_a?(Array)

        address_data.map do |addr|
          Ammitto::Address.new(
            street: addr['street'],
            city: addr['city'],
            state: addr['state'],
            country: addr['country'],
            postal_code: addr['zip']
          )
        end
      end

      def build_identifications(data)
        ids = []

        # Passport
        if data['passport']
          ids << Ammitto::Identification.new(
            type: 'Passport',
            number: data['passport']
          )
        end

        # Tax ID
        if data['tax_id']
          ids << Ammitto::Identification.new(
            type: 'Tax ID',
            number: data['tax_id']
          )
        end

        ids
      end

      def build_source_reference(data, source_code)
        Ammitto::SourceReference.new(
          source_code: source_code.to_s,
          reference_number: data['ref_number'],
          url: data['ref_type']
        )
      end

      def build_authority(source_code)
        Ammitto::Authority.find(source_code.to_s)
      rescue StandardError
        nil
      end

      def build_regime(data, source_code)
        programme = data['programme']
        return nil unless programme

        Ammitto::SanctionRegime.new(
          code: programme,
          name: regime_name_for_code(programme, source_code)
        )
      end

      def regime_name_for_code(code, _source_code)
        regime_names = {
          'IRQ' => 'Iraq',
          'DPRK' => "Democratic People's Republic of Korea",
          'IRN' => 'Iran',
          'LIB' => 'Libya',
          'SOM' => 'Somalia',
          'SYR' => 'Syria',
          'MLI' => 'Mali',
          'CAF' => 'Central African Republic',
          'YEM' => 'Yemen',
          'AFG' => 'Afghanistan',
          'GUINEA-BISSAU' => 'Guinea-Bissau',
          'RUSSIA' => 'Russia/Ukraine',
          'BDI' => 'Burundi',
          'TUN' => 'Tunisia',
          'EGY' => 'Egypt',
          'LBY' => 'Libya',
          'SSD' => 'South Sudan',
          'VEN' => 'Venezuela',
          'UKRAINE' => 'Russia/Ukraine'
        }
        regime_names[code] || code
      end

      def build_legal_bases(data, _source_code)
        regulations = data['regulations']
        return [] unless regulations.is_a?(Array)

        regulations.map do |reg|
          Ammitto::LegalInstrument.new(
            type: map_instrument_type(reg['type']),
            identifier: reg['number_title'],
            title: reg['number_title'],
            issuing_body: 'Council of the European Union',
            issuance_date: reg['publication_date'],
            url: reg['publication_url']
          )
        end
      end

      def map_instrument_type(type)
        return 'regulation' unless type

        case type.downcase
        when 'regulation' then 'regulation'
        when 'decision' then 'decision'
        when 'directive' then 'directive'
        else 'regulation'
        end
      end

      def build_effects(data, _entity)
        effects = []
        entity_type = data['entity_type']

        # EU sanctions typically include asset freeze for all entity types
        effects << Ammitto::SanctionEffect.new(
          effect_type: 'asset_freeze',
          scope: 'full',
          description: 'All funds and economic resources belonging to or owned by this entity are frozen.'
        )

        # Travel ban applies to persons
        if entity_type == 'person'
          effects << Ammitto::SanctionEffect.new(
            effect_type: 'travel_ban',
            scope: 'full',
            description: 'Travel restrictions apply to this individual.'
          )
        end

        effects
      end

      def map_status(status)
        return 'active' unless status

        case status.downcase
        when 'active', 'listed' then 'active'
        when 'suspended' then 'suspended'
        when 'delisted', 'removed' then 'delisted'
        when 'expired' then 'expired'
        when 'deceased' then 'deceased'
        else 'active'
        end
      end

      def build_period(data)
        Ammitto::TemporalPeriod.new(
          listed_date: data['listed_date'] || data['listedDate'],
          last_updated: Time.now.iso8601
        )
      end

      def build_raw_data(data, source_code)
        Ammitto::RawSourceData.new(
          source_file: "#{source_code}-data",
          source_format: 'yaml',
          source_specific_fields: data.except('names', 'entity_type', 'country', 'birthdate', 'address', 'passport', 'tax_id', 'ref_number',
                                              'ref_type', 'remark')
        )
      end

      def export_source_file(source_code, entities, entries)
        FileUtils.mkdir_p(File.join(output_dir, 'api', 'v1', 'sources'))

        json_ld = serializer.serialize_document(
          entities: entities,
          entries: entries
        )

        output_path = File.join(output_dir, 'api', 'v1', 'sources', "#{source_code}.jsonld")
        File.write(output_path, serializer.to_json(json_ld))

        Logger.info("Exported #{entities.length} entities to #{output_path}")
        output_path
      end

      def export_combined(all_entities, all_entries)
        FileUtils.mkdir_p(File.join(output_dir, 'api', 'v1'))

        json_ld = serializer.serialize_document(
          entities: all_entities,
          entries: all_entries
        )

        output_path = File.join(output_dir, 'api', 'v1', 'all.jsonld')
        File.write(output_path, serializer.to_json(json_ld))

        Logger.info("Exported combined file with #{all_entities.length} entities to #{output_path}")
        output_path
      end
    end
  end
end
