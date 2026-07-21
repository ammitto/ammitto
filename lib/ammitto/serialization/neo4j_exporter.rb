# frozen_string_literal: true

# Neo4j CSV Exporter for Ammitto Knowledge Graph
#
# Generates CSV files compatible with Neo4j's LOAD CSV import.
# Creates separate files for nodes and relationships.
#
# @example Using the exporter
#   exporter = Neo4jExporter.new
#   exporter.add_source(processed_dir)
#   exporter.export('./neo4j_import')
#
# Then in Neo4j:
#   :auto USING PERIODIC COMMIT 1000
#   LOAD CSV WITH HEADERS FROM 'file:///entities.csv' AS row
#   MERGE (e:Entity {id: row.id}) ...

require 'csv'
require 'fileutils'
require 'yaml'

module Ammitto
  module Serialization
    class Neo4jExporter
      # ISO 3166-1 alpha-2 country codes (common ones)
      COUNTRY_CODES = {
        'AF' => 'Afghanistan', 'AL' => 'Albania', 'DZ' => 'Algeria',
        'AU' => 'Australia', 'AT' => 'Austria', 'AZ' => 'Azerbaijan',
        'BH' => 'Bahrain', 'BD' => 'Bangladesh', 'BY' => 'Belarus',
        'BE' => 'Belgium', 'BA' => 'Bosnia and Herzegovina', 'BR' => 'Brazil',
        'BG' => 'Bulgaria', 'CA' => 'Canada', 'CN' => 'China',
        'HR' => 'Croatia', 'CY' => 'Cyprus', 'CZ' => 'Czech Republic',
        'DK' => 'Denmark', 'EG' => 'Egypt', 'EE' => 'Estonia',
        'FI' => 'Finland', 'FR' => 'France', 'GE' => 'Georgia',
        'DE' => 'Germany', 'GR' => 'Greece', 'HK' => 'Hong Kong',
        'HU' => 'Hungary', 'IS' => 'Iceland', 'IN' => 'India',
        'ID' => 'Indonesia', 'IR' => 'Iran', 'IQ' => 'Iraq',
        'IE' => 'Ireland', 'IL' => 'Israel', 'IT' => 'Italy',
        'JP' => 'Japan', 'JO' => 'Jordan', 'KZ' => 'Kazakhstan',
        'KE' => 'Kenya', 'KP' => 'North Korea', 'KR' => 'South Korea',
        'KW' => 'Kuwait', 'KG' => 'Kyrgyzstan', 'LV' => 'Latvia',
        'LB' => 'Lebanon', 'LY' => 'Libya', 'LT' => 'Lithuania',
        'LU' => 'Luxembourg', 'MY' => 'Malaysia', 'MT' => 'Malta',
        'MX' => 'Mexico', 'MD' => 'Moldova', 'ME' => 'Montenegro',
        'MA' => 'Morocco', 'MM' => 'Myanmar', 'NL' => 'Netherlands',
        'NZ' => 'New Zealand', 'NG' => 'Nigeria', 'NO' => 'Norway',
        'PK' => 'Pakistan', 'PS' => 'Palestine', 'PH' => 'Philippines',
        'PL' => 'Poland', 'PT' => 'Portugal', 'QA' => 'Qatar',
        'RO' => 'Romania', 'RU' => 'Russia', 'SA' => 'Saudi Arabia',
        'RS' => 'Serbia', 'SG' => 'Singapore', 'SK' => 'Slovakia',
        'SI' => 'Slovenia', 'ZA' => 'South Africa', 'ES' => 'Spain',
        'SD' => 'Sudan', 'SE' => 'Sweden', 'CH' => 'Switzerland',
        'SY' => 'Syria', 'TW' => 'Taiwan', 'TJ' => 'Tajikistan',
        'TH' => 'Thailand', 'TN' => 'Tunisia', 'TR' => 'Turkey',
        'TM' => 'Turkmenistan', 'UA' => 'Ukraine', 'AE' => 'United Arab Emirates',
        'GB' => 'United Kingdom', 'US' => 'United States', 'UZ' => 'Uzbekistan',
        'VE' => 'Venezuela', 'VN' => 'Vietnam', 'YE' => 'Yemen',
        'EU' => 'European Union', 'UN' => 'United Nations', 'WB' => 'World Bank'
      }.freeze

      # Authority registry
      AUTHORITIES = {
        'au' => { name: 'Australia DFAT', country: 'AU' },
        'ca' => { name: 'Canada Global Affairs', country: 'CA' },
        'ch' => { name: 'Switzerland SECO', country: 'CH' },
        'cn' => { name: 'China MOFCOM', country: 'CN' },
        'eu' => { name: 'European Union', country: 'EU' },
        'eu-vessels' => { name: 'EU Vessels', country: 'EU' },
        'jp' => { name: 'Japan METI', country: 'JP' },
        'nz' => { name: 'New Zealand MFAT', country: 'NZ' },
        'ru' => { name: 'Russia MID', country: 'RU' },
        'tr' => { name: 'Turkey', country: 'TR' },
        'uk' => { name: 'UK OFSI', country: 'GB' },
        'un' => { name: 'United Nations', country: 'UN' },
        'un-vessels' => { name: 'UN Vessels', country: 'UN' },
        'us' => { name: 'US OFAC', country: 'US' },
        'wb' => { name: 'World Bank', country: 'WB' }
      }.freeze

      attr_reader :entities, :entries, :authorities, :announcements,
                  :legal_instruments, :countries, :names, :addresses,
                  :identifiers, :regimes

      def initialize
        @entities = {}
        @entries = []
        @authorities = {}
        @announcements = {}
        @legal_instruments = {}
        @countries = {}
        @names = []
        @addresses = []
        @identifiers = []
        @regimes = {}
        @name_id_counter = 0
        @address_id_counter = 0
        @identifier_id_counter = 0
      end

      # Add data from a processed directory
      # @param processed_dir [String] path to processed directory
      # @param source_code [String] source code (e.g., 'uk', 'eu')
      def add_source(processed_dir, source_code = nil)
        source_code ||= detect_source_code(processed_dir)
        return unless source_code

        # Add authority
        add_authority(source_code)

        # Load entities
        load_entities(processed_dir, source_code)

        # Load entries
        load_entries(processed_dir, source_code)

        # Load announcements
        load_announcements(processed_dir, source_code)

        # Load legal instruments
        load_legal_instruments(processed_dir, source_code)
      end

      # Export to CSV files
      # @param output_dir [String] output directory
      def export(output_dir)
        FileUtils.mkdir_p(output_dir)

        puts "Exporting Neo4j CSV files to #{output_dir}..."

        export_entities_csv(output_dir)
        export_entries_csv(output_dir)
        export_authorities_csv(output_dir)
        export_announcements_csv(output_dir)
        export_legal_instruments_csv(output_dir)
        export_countries_csv(output_dir)
        export_names_csv(output_dir)
        export_addresses_csv(output_dir)
        export_identifiers_csv(output_dir)
        export_regimes_csv(output_dir)
        export_relationships_csv(output_dir)

        puts 'Export complete!'
        puts "  Entities: #{@entities.size}"
        puts "  Entries: #{@entries.size}"
        puts "  Authorities: #{@authorities.size}"
        puts "  Countries: #{@countries.size}"
        puts "  Names: #{@names.size}"
        puts "  Addresses: #{@addresses.size}"
        puts "  Identifiers: #{@identifiers.size}"
      end

      private

      def detect_source_code(processed_dir)
        index_file = File.join(processed_dir, '_index.yaml')
        if File.exist?(index_file)
          index = YAML.load_file(index_file)
          return index['source'] if index&.key?('source')
        end

        File.basename(File.dirname(processed_dir)).gsub(/^data-/, '')
      end

      def add_authority(code)
        return if @authorities.key?(code)

        info = AUTHORITIES[code] || { name: code.upcase, country: 'XX' }
        @authorities[code] = {
          code: code,
          name: info[:name],
          country_code: info[:country]
        }

        # Add country if not exists
        add_country(info[:country])
      end

      def add_country(code)
        return if code.nil? || code.empty? || @countries.key?(code)

        @countries[code] = {
          code: code,
          name: COUNTRY_CODES[code] || code
        }
      end

      def load_entities(processed_dir, source_code)
        entities_dir = File.join(processed_dir, 'entities')
        return unless File.directory?(entities_dir)

        Dir.glob(File.join(entities_dir, '*.yaml')).each do |file|
          data = YAML.load_file(file)
          next unless data.is_a?(Hash) && data['id']

          entity_id = data['id']
          full_id = "#{source_code}/#{entity_id}"

          # Extract names
          entity_names = extract_names(data, full_id)

          # Extract primary name
          primary_name = entity_names.find { |n| n[:is_primary] }&.dig(:full_name)

          # Store entity
          @entities[full_id] = {
            id: full_id,
            local_id: entity_id,
            source: source_code,
            type: normalize_entity_type(data['type'] || data['entity_type']),
            primary_name: primary_name,
            remarks: sanitize_for_csv(data['remarks'])
          }

          # Add names to collection
          @names.concat(entity_names)

          # Extract addresses
          extract_addresses(data, full_id)

          # Extract identifiers
          extract_identifiers(data, full_id)

          # Extract countries from nationalities
          if data['nationalities'].is_a?(Array)
            data['nationalities'].each do |nat|
              code = normalize_country_code(nat)
              add_country(code) if code
            end
          end

          # Extract countries from birth info
          next unless data['birth_info'].is_a?(Array)

          data['birth_info'].each do |birth|
            code = normalize_country_code(birth['country'] || birth['country_code'])
            add_country(code) if code
          end
        end
      end

      def extract_names(data, entity_id)
        names = []

        if data['names'].is_a?(Array)
          data['names'].each do |name|
            next unless name.is_a?(Hash)

            full_name = name['english'] || name['full_name'] || name['fullName'] || name['name']
            next if full_name.nil? || full_name.to_s.strip.empty?

            @name_id_counter += 1
            names << {
              id: "name-#{@name_id_counter}",
              entity_id: entity_id,
              full_name: sanitize_for_csv(full_name),
              is_primary: name['is_primary'] || name['isPrimary'] || false,
              script: normalize_script(name['script'] || name['name_script']),
              language: name['language'] || name['lang']
            }
          end
        end

        names
      end

      def extract_addresses(data, entity_id)
        return unless data['addresses'].is_a?(Array)

        data['addresses'].each do |addr|
          @address_id_counter += 1
          country_code = normalize_country_code(
            addr['country'] || addr['country_code'] || addr['countryCode']
          )

          add_country(country_code) if country_code

          @addresses << {
            id: "addr-#{@address_id_counter}",
            entity_id: entity_id,
            street: addr['street'] || addr['address_details'],
            city: addr['city'],
            state: addr['state'] || addr['province'],
            postal_code: addr['postal_code'] || addr['zip_code'],
            country_code: country_code,
            care_of: addr['care_of'] || addr['c-o']
          }.compact
        end
      end

      def extract_identifiers(data, entity_id)
        # From identifications/identifiers array
        ids = data['identifications'] || data['identifiers'] || []
        ids = [ids] unless ids.is_a?(Array)

        ids.each do |id|
          next unless id.is_a?(Hash)

          @identifier_id_counter += 1
          country_code = normalize_country_code(id['country'] || id['country_code'])

          add_country(country_code) if country_code

          @identifiers << {
            id: "id-#{@identifier_id_counter}",
            entity_id: entity_id,
            type: id['type'] || id['document_type'],
            value: id['value'] || id['identification'] || id['number'],
            country_code: country_code,
            issue_date: id['issue_date'],
            expiry_date: id['expiry_date']
          }.compact
        end
      end

      def load_entries(processed_dir, source_code)
        entries_dir = File.join(processed_dir, 'entries')
        return unless File.directory?(entries_dir)

        Dir.glob(File.join(entries_dir, '*.yaml')).each do |file|
          data = YAML.load_file(file)
          next unless data.is_a?(Hash)

          entity_local_id = data['entity_id']
          entity_full_id = "#{source_code}/#{entity_local_id}"

          # Generate entry ID
          entry_id = data['id'] || "entry-#{entity_local_id}"
          full_entry_id = "#{source_code}/#{entry_id}"

          # Extract regime if present
          regime_code = extract_regime_code(data)
          if regime_code && !@regimes.key?(regime_code)
            @regimes[regime_code] = {
              code: regime_code,
              name: format_regime_name(regime_code)
            }
          end

          @entries << {
            id: full_entry_id,
            local_id: entry_id,
            entity_id: entity_full_id,
            authority_code: source_code,
            announcement_id: data['announcement_id'],
            list_type: data['list_type'],
            status: data['status'] || 'active',
            listed_date: data['listed_date'],
            delisted_date: data['delisted_date'],
            measures: (data['measures'] || []).join(';'),
            regime_code: regime_code,
            legal_instrument_ids: (data['legal_instrument_ids'] || []).join(';')
          }.compact
        end
      end

      def extract_regime_code(data)
        # Try various fields that might contain regime info
        regime = data['regime']
        if regime.is_a?(Hash)
          return regime['code'] || regime['name']
        elsif regime.is_a?(String)
          return regime
        end

        # Try to extract from remarks or list_type
        nil
      end

      def format_regime_name(code)
        return nil unless code

        code.to_s.split(/[-_]/).map(&:capitalize).join(' ')
      end

      def load_announcements(processed_dir, source_code)
        announcements_dir = File.join(processed_dir, 'announcements')
        return unless File.directory?(announcements_dir)

        Dir.glob(File.join(announcements_dir, '*.yaml')).each do |file|
          data = YAML.load_file(file)
          next unless data.is_a?(Hash) && data['id']

          full_id = "#{source_code}/#{data['id']}"

          @announcements[full_id] = {
            id: full_id,
            local_id: data['id'],
            source: source_code,
            title: data['title'] || data['name'],
            number: data['number'],
            date: data['date'],
            effective_date: data['effective_date'],
            issuing_authority: data['issuing_authority'],
            measures: (data['measures'] || []).join(';')
          }.compact
        end
      end

      def load_legal_instruments(processed_dir, source_code)
        instruments_dir = File.join(processed_dir, 'legal_instruments')
        return unless File.directory?(instruments_dir)

        Dir.glob(File.join(instruments_dir, '*.yaml')).each do |file|
          data = YAML.load_file(file)
          next unless data.is_a?(Hash) && data['id']

          full_id = "#{source_code}/#{data['id']}"

          @legal_instruments[full_id] = {
            id: full_id,
            local_id: data['id'],
            source: source_code,
            name: data['name_english'] || data['name'] || data['short_name'],
            short_name: data['short_name'],
            enacted_date: data['enacted_date'],
            amended_date: data['amended_date']
          }.compact
        end
      end

      def normalize_entity_type(type)
        return 'organization' if type.nil?

        type = type.to_s.downcase
        case type
        when 'person', 'individual' then 'person'
        when 'organization', 'organisation', 'entity', 'company' then 'organization'
        when 'vessel', 'ship' then 'vessel'
        when 'aircraft', 'plane' then 'aircraft'
        else 'organization'
        end
      end

      def normalize_country_code(code)
        return nil if code.nil? || code.to_s.strip.empty?

        code = code.to_s.strip.upcase

        # Already a valid 2-letter code
        return code if code.length == 2 && COUNTRY_CODES.key?(code)

        # Try to match country name
        COUNTRY_CODES.each do |cc, name|
          return cc if name.downcase == code.downcase
        end

        # Return as-is if looks like a code
        code.length == 2 ? code : nil
      end

      def normalize_script(script)
        return 'Latn' if script.nil?

        case script.to_s.downcase
        when 'latn', 'latin', 'lat' then 'Latn'
        when 'cyrl', 'cyrillic' then 'Cyrl'
        when 'hani', 'chinese', 'han' then 'Hani'
        when 'arab', 'arabic' then 'Arab'
        else script.to_s.capitalize
        end
      end

      def sanitize_for_csv(value)
        return nil if value.nil?

        # Convert to string and remove or escape problematic characters
        str = value.to_s
        # Replace newlines with space, remove tabs
        str = str.gsub(/[\n\r\t]/, ' ')
        # Replace double quotes with single quotes
        str = str.gsub('"', "'")
        # Remove any remaining control characters
        str = str.gsub(/[\x00-\x1F]/, '')
        # Trim and limit length
        str.strip[0..500]
      end

      # CSV Export Methods

      def export_entities_csv(dir)
        CSV.open(File.join(dir, 'entities.csv'), 'w') do |csv|
          csv << %w[id local_id source type primary_name remarks]
          @entities.each_value do |e|
            csv << [e[:id], e[:local_id], e[:source], e[:type], e[:primary_name], e[:remarks]]
          end
        end
        puts "  Exported entities.csv (#{@entities.size} records)"
      end

      def export_entries_csv(dir)
        CSV.open(File.join(dir, 'entries.csv'), 'w') do |csv|
          csv << %w[id local_id entity_id authority_code announcement_id list_type status listed_date delisted_date
                    measures regime_code]
          @entries.each do |e|
            csv << [e[:id], e[:local_id], e[:entity_id], e[:authority_code],
                    e[:announcement_id], e[:list_type], e[:status], e[:listed_date],
                    e[:delisted_date], e[:measures], e[:regime_code]]
          end
        end
        puts "  Exported entries.csv (#{@entries.size} records)"
      end

      def export_authorities_csv(dir)
        CSV.open(File.join(dir, 'authorities.csv'), 'w') do |csv|
          csv << %w[code name country_code]
          @authorities.each_value do |a|
            csv << [a[:code], a[:name], a[:country_code]]
          end
        end
        puts "  Exported authorities.csv (#{@authorities.size} records)"
      end

      def export_announcements_csv(dir)
        CSV.open(File.join(dir, 'announcements.csv'), 'w') do |csv|
          csv << %w[id local_id source title number date effective_date issuing_authority]
          @announcements.each_value do |a|
            csv << [a[:id], a[:local_id], a[:source], a[:title], a[:number],
                    a[:date], a[:effective_date], a[:issuing_authority]]
          end
        end
        puts "  Exported announcements.csv (#{@announcements.size} records)"
      end

      def export_legal_instruments_csv(dir)
        CSV.open(File.join(dir, 'legal_instruments.csv'), 'w') do |csv|
          csv << %w[id local_id source name short_name enacted_date amended_date]
          @legal_instruments.each_value do |li|
            csv << [li[:id], li[:local_id], li[:source], li[:name],
                    li[:short_name], li[:enacted_date], li[:amended_date]]
          end
        end
        puts "  Exported legal_instruments.csv (#{@legal_instruments.size} records)"
      end

      def export_countries_csv(dir)
        CSV.open(File.join(dir, 'countries.csv'), 'w') do |csv|
          csv << %w[code name]
          @countries.each_value do |c|
            csv << [c[:code], c[:name]]
          end
        end
        puts "  Exported countries.csv (#{@countries.size} records)"
      end

      def export_names_csv(dir)
        CSV.open(File.join(dir, 'names.csv'), 'w') do |csv|
          csv << %w[id entity_id full_name is_primary script language]
          @names.each do |n|
            csv << [n[:id], n[:entity_id], sanitize_for_csv(n[:full_name]), n[:is_primary],
                    n[:script], n[:language]]
          end
        end
        puts "  Exported names.csv (#{@names.size} records)"
      end

      def export_addresses_csv(dir)
        CSV.open(File.join(dir, 'addresses.csv'), 'w') do |csv|
          csv << %w[id entity_id street city state postal_code country_code care_of]
          @addresses.each do |a|
            csv << [a[:id], a[:entity_id], a[:street], a[:city], a[:state],
                    a[:postal_code], a[:country_code], a[:care_of]]
          end
        end
        puts "  Exported addresses.csv (#{@addresses.size} records)"
      end

      def export_identifiers_csv(dir)
        CSV.open(File.join(dir, 'identifiers.csv'), 'w') do |csv|
          csv << %w[id entity_id type value country_code issue_date expiry_date]
          @identifiers.each do |i|
            csv << [i[:id], i[:entity_id], i[:type], i[:value],
                    i[:country_code], i[:issue_date], i[:expiry_date]]
          end
        end
        puts "  Exported identifiers.csv (#{@identifiers.size} records)"
      end

      def export_regimes_csv(dir)
        CSV.open(File.join(dir, 'regimes.csv'), 'w') do |csv|
          csv << %w[code name]
          @regimes.each_value do |r|
            csv << [r[:code], r[:name]]
          end
        end
        puts "  Exported regimes.csv (#{@regimes.size} records)"
      end

      def export_relationships_csv(dir)
        # Entry -> Entity relationship
        CSV.open(File.join(dir, 'rel_entry_entity.csv'), 'w') do |csv|
          csv << %w[entry_id entity_id]
          @entries.each do |e|
            csv << [e[:id], e[:entity_id]]
          end
        end

        # Entry -> Authority relationship
        CSV.open(File.join(dir, 'rel_entry_authority.csv'), 'w') do |csv|
          csv << %w[entry_id authority_code]
          @entries.each do |e|
            csv << [e[:id], e[:authority_code]]
          end
        end

        # Entry -> Announcement relationship
        CSV.open(File.join(dir, 'rel_entry_announcement.csv'), 'w') do |csv|
          csv << %w[entry_id announcement_id]
          @entries.each do |e|
            next unless e[:announcement_id]

            # Resolve announcement ID
            ann_id = resolve_announcement_id(e[:announcement_id], e[:authority_code])
            csv << [e[:id], ann_id] if ann_id
          end
        end

        # Entry -> Regime relationship
        CSV.open(File.join(dir, 'rel_entry_regime.csv'), 'w') do |csv|
          csv << %w[entry_id regime_code]
          @entries.each do |e|
            csv << [e[:id], e[:regime_code]] if e[:regime_code]
          end
        end

        # Entity -> Name relationship
        CSV.open(File.join(dir, 'rel_entity_name.csv'), 'w') do |csv|
          csv << %w[entity_id name_id]
          @names.each do |n|
            csv << [n[:entity_id], n[:id]]
          end
        end

        # Entity -> Address relationship
        CSV.open(File.join(dir, 'rel_entity_address.csv'), 'w') do |csv|
          csv << %w[entity_id address_id]
          @addresses.each do |a|
            csv << [a[:entity_id], a[:id]]
          end
        end

        # Entity -> Identifier relationship
        CSV.open(File.join(dir, 'rel_entity_identifier.csv'), 'w') do |csv|
          csv << %w[entity_id identifier_id]
          @identifiers.each do |i|
            csv << [i[:entity_id], i[:id]]
          end
        end

        # Address -> Country relationship
        CSV.open(File.join(dir, 'rel_address_country.csv'), 'w') do |csv|
          csv << %w[address_id country_code]
          @addresses.each do |a|
            csv << [a[:id], a[:country_code]] if a[:country_code]
          end
        end

        # Identifier -> Country relationship
        CSV.open(File.join(dir, 'rel_identifier_country.csv'), 'w') do |csv|
          csv << %w[identifier_id country_code]
          @identifiers.each do |i|
            csv << [i[:id], i[:country_code]] if i[:country_code]
          end
        end

        # Authority -> Country relationship
        CSV.open(File.join(dir, 'rel_authority_country.csv'), 'w') do |csv|
          csv << %w[authority_code country_code]
          @authorities.each_value do |a|
            csv << [a[:code], a[:country_code]] if a[:country_code]
          end
        end

        puts '  Exported relationship CSV files'
      end

      def resolve_announcement_id(local_id, source_code)
        # Try with source prefix
        full_id = "#{source_code}/#{local_id}"
        return full_id if @announcements.key?(full_id)

        # Try without source prefix
        @announcements.each_key do |key|
          return key if key.end_with?("/#{local_id}")
        end

        # Return local ID as fallback
        local_id
      end
    end
  end
end
