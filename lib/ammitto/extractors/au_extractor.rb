# frozen_string_literal: true

require_relative 'base_extractor'
require_relative 'registry'
require 'roo'

module Ammitto
  module Extractors
    # AuExtractor extracts sanctions data from Australia (DFAT)
    #
    # Source: https://www.dfat.gov.au/sites/default/files/Australian_Sanctions_Consolidated_List.xlsx
    # Format: XLSX
    #
    # Australia data structure:
    # - Reference numbers with variants (8577, 8577a, 8577b) represent ONE entity
    # - Name Types: Primary Name, Original Script, Alias
    # - Entity Types: Individual, Entity, Vessel
    # - Sanction Effects as boolean columns: Targeted Financial Sanction, Travel Ban, Arms Embargo, Maritime Restriction
    #
    class AuExtractor < BaseExtractor
      # Header mapping from spreadsheet columns to internal keys
      HEADER_MAP = {
        'Reference' => :reference,
        'Name of Individual or Entity' => :name,
        'Type' => :entity_type,
        'Name Type' => :name_type,
        'Alias Strength' => :alias_strength,
        'Date of Birth' => :date_of_birth,
        'Place of Birth' => :place_of_birth,
        'Citizenship' => :citizenship,
        'Address' => :address,
        'Additional Information' => :additional_info,
        'Listing Information' => :listing_info,
        'IMO Number' => :imo_number,
        'Committees' => :committee,
        'Control Date' => :control_date,
        'Instrument of Designation' => :instrument,
        'Targeted Financial Sanction' => :targeted_financial_sanction,
        'Travel Ban' => :travel_ban,
        'Arms Embargo' => :arms_embargo,
        'Maritime Restriction' => :maritime_restriction
      }.freeze

      attr_accessor :verbose

      # @return [Symbol] the source code
      def code
        :au
      end

      # @return [String] authority name
      def authority_name
        'Australia (DFAT)'
      end

      # @return [String] API endpoint
      def api_endpoint
        'https://www.dfat.gov.au/sites/default/files/Australian_Sanctions_Consolidated_List.xlsx'
      end

      # Fetch raw data from Australia
      # @return [String] path to downloaded XLSX temp file
      def fetch
        require 'open-uri'
        require 'tempfile'

        puts "[#{code}] Downloading from #{api_endpoint}" if verbose

        # Download XLSX to temp file
        @temp_file = Tempfile.new(['au_sanctions', '.xlsx'])
        URI.open(api_endpoint, 'User-Agent' => 'Mozilla/5.0') do |remote_file|
          @temp_file.write(remote_file.read)
        end
        @temp_file.close

        @temp_file.path
      end

      # Clean up temp file after processing
      def cleanup
        @temp_file&.unlink
        @temp_file = nil
      end

      # Extract entities from Australia XLSX
      # @param data [Hash] fetched data with grouped rows
      # @return [Array<Hash>]
      def extract_entities(data)
        return [] unless data && data[:grouped]

        data[:grouped].map do |base_ref, rows|
          build_entity(base_ref, rows)
        end.compact
      end

      # Extract sanction entries from Australia XLSX
      # @param data [Hash] fetched data with grouped rows
      # @return [Array<Hash>]
      def extract_entries(data)
        return [] unless data && data[:grouped]

        data[:grouped].map do |base_ref, rows|
          build_entry(base_ref, rows)
        end.compact
      end

      private

      # Parse XLSX file
      # @param path [String] path to XLSX file
      # @return [Array<Hash>] parsed rows
      def parse_xlsx(path)
        xlsx = Roo::Excelx.new(path)
        sheet = xlsx.sheet(0)

        # Get headers from first row
        headers = sheet.row(1).map do |h|
          header_key = HEADER_MAP[h.to_s.strip]
          header_key || h.to_s.strip.downcase.gsub(/\s+/, '_').to_sym
        end

        rows = []
        (2..sheet.last_row).each do |row_num|
          values = sheet.row(row_num)
          row = {}

          headers.each_with_index do |header, idx|
            row[header] = values[idx]&.to_s&.strip
          end

          rows << row unless row[:reference].nil? || row[:reference].empty?
        end

        rows
      end

      # Group rows by base reference (strip trailing letters)
      # @param rows [Array<Hash>]
      # @return [Hash] { base_ref => [rows...] }
      def group_by_base_reference(rows)
        rows.group_by do |row|
          # Extract base reference: "8577a" → "8577"
          row[:reference].to_s.gsub(/[a-z]+$/i, '')
        end
      end

      # Build entity from grouped rows
      # @param base_ref [String] base reference number
      # @param rows [Array<Hash>] all rows for this entity
      # @return [Hash]
      def build_entity(base_ref, rows)
        # Find primary row (Primary Name)
        primary_row = rows.find { |r| r[:name_type] == 'Primary Name' } || rows.first

        entity_type = map_entity_type(primary_row[:entity_type])
        entity_id = generate_entity_id(code, base_ref)

        entity = {
          '@id' => entity_id,
          '@type' => entity_type == 'person' ? 'PersonEntity' :
                     entity_type == 'vessel' ? 'VesselEntity' : 'OrganizationEntity',
          'entityType' => entity_type,
          'names' => build_names(rows),
          'sourceReferences' => [{
            '@type' => 'SourceReference',
            'sourceCode' => 'au',
            'referenceNumber' => base_ref
          }]
        }

        # Add entity-specific fields
        case entity_type
        when 'person'
          entity.merge!(build_person_fields(primary_row))
        when 'vessel'
          entity.merge!(build_vessel_fields(primary_row))
        when 'organization'
          entity.merge!(build_organization_fields(primary_row))
        end

        entity.compact
      end

      # Build names array from rows
      # @param rows [Array<Hash>]
      # @return [Array<Hash>]
      def build_names(rows)
        rows.map do |row|
          name = {
            '@type' => 'NameVariant',
            'fullName' => row[:name],
            'isPrimary' => row[:name_type] == 'Primary Name'
          }

          # Detect script
          case row[:name_type]
          when 'Original Script'
            name['script'] = detect_script(row[:name])
          else
            name['script'] = 'Latn'
          end

          # Add alias info
          if row[:name_type] == 'Alias'
            name['nameType'] = 'alias'
            name['strength'] = row[:alias_strength]&.downcase
          end

          name.compact
        end
      end

      # Build person-specific fields
      # @param row [Hash]
      # @return [Hash]
      def build_person_fields(row)
        fields = {}

        # Birth info
        if row[:date_of_birth] || row[:place_of_birth]
          birth_info = { '@type' => 'BirthInfo' }

          if row[:date_of_birth]
            # Handle multiple dates: "5 May 1957, April 1957, May 1957"
            dates = row[:date_of_birth].split(',').map(&:strip)
            birth_info['date'] = parse_au_date(dates.first)
            birth_info['alternativeDates'] = dates.drop(1).map { |d| parse_au_date(d) }.compact if dates.length > 1
          end

          birth_info['place'] = row[:place_of_birth] if row[:place_of_birth]
          fields['birthInfo'] = [birth_info.compact]
        end

        # Citizenship
        fields['nationalities'] = [row[:citizenship]] if row[:citizenship]

        # Additional info as remarks
        fields['remarks'] = row[:additional_info] if row[:additional_info]

        fields
      end

      # Build vessel-specific fields
      # @param row [Hash]
      # @return [Hash]
      def build_vessel_fields(row)
        fields = {}

        # IMO Number
        if row[:imo_number]
          fields['identifications'] = [{
            '@type' => 'Identification',
            'type' => 'IMO',
            'number' => row[:imo_number]
          }]
        end

        # Additional info
        fields['remarks'] = row[:additional_info] if row[:additional_info]

        fields
      end

      # Build organization-specific fields
      # @param row [Hash]
      # @return [Hash]
      def build_organization_fields(row)
        fields = {}

        # Address
        if row[:address]
          fields['addresses'] = [{
            '@type' => 'Address',
            'fullAddress' => row[:address]
          }]
        end

        # Additional info
        fields['remarks'] = row[:additional_info] if row[:additional_info]

        fields
      end

      # Build sanction entry from grouped rows
      # @param base_ref [String]
      # @param rows [Array<Hash>]
      # @return [Hash]
      def build_entry(base_ref, rows)
        primary_row = rows.find { |r| r[:name_type] == 'Primary Name' } || rows.first

        entity_id = generate_entity_id(code, base_ref)
        entry_id = generate_entry_id(code, base_ref)

        {
          '@id' => entry_id,
          '@type' => 'SanctionEntry',
          'entityId' => entity_id,
          'authority' => {
            '@type' => 'Authority',
            'id' => 'au',
            'name' => 'Australia (DFAT)',
            'countryCode' => 'AU'
          },
          'referenceNumber' => base_ref,
          'status' => 'active',
          'regime' => {
            '@type' => 'SanctionRegime',
            'name' => primary_row[:committee],
            'code' => regime_code(primary_row[:committee])
          },
          'effects' => build_effects(primary_row),
          'period' => build_period(primary_row),
          'rawSourceData' => {
            '@type' => 'RawSourceData',
            'sourceFormat' => 'xlsx',
            'sourceSpecificFields' => {
              'au:committee' => primary_row[:committee],
              'au:control_date' => primary_row[:control_date],
              'au:instrument' => primary_row[:instrument],
              'au:listing_info' => primary_row[:listing_info],
              'au:name_variants' => rows.map { |r| { ref: r[:reference], type: r[:name_type] } }
            }.compact
          }
        }
      end

      # Build effects array from boolean columns
      # @param row [Hash]
      # @return [Array<Hash>]
      def build_effects(row)
        effects = []

        if row[:targeted_financial_sanction] == 'TRUE'
          effects << { '@type' => 'SanctionEffect', 'effectType' => 'asset_freeze', 'scope' => 'full' }
        end

        if row[:travel_ban] == 'TRUE'
          effects << { '@type' => 'SanctionEffect', 'effectType' => 'entry_ban', 'scope' => 'full' }
        end

        if row[:arms_embargo] == 'TRUE'
          effects << { '@type' => 'SanctionEffect', 'effectType' => 'arms_embargo', 'scope' => 'full' }
        end

        if row[:maritime_restriction] == 'TRUE'
          effects << { '@type' => 'SanctionEffect', 'effectType' => 'maritime_restriction', 'scope' => 'full' }
        end

        effects
      end

      # Build period from row
      # @param row [Hash]
      # @return [Hash, nil]
      def build_period(row)
        return nil unless row[:control_date]

        {
          '@type' => 'TemporalPeriod',
          'listedDate' => parse_au_date(row[:control_date])
        }
      end

      # Map entity type from AU format
      # @param type [String]
      # @return [String]
      def map_entity_type(type)
        case type.to_s.downcase
        when 'individual'
          'person'
        when 'entity'
          'organization'
        when 'vessel'
          'vessel'
        else
          'organization'
        end
      end

      # Detect script from text
      # @param text [String]
      # @return [String]
      def detect_script(text)
        return 'Latn' if text.nil? || text.empty?

        # Arabic
        return 'Arab' if text.match?(/\p{Arabic}/)

        # Cyrillic
        return 'Cyrl' if text.match?(/\p{Cyrillic}/)

        # Chinese/Japanese/Korean
        return 'Hani' if text.match?(/\p{Han}/)

        # Default to Latin
        'Latn'
      end

      # Parse Australian date format
      # @param date_str [String]
      # @return [String, nil] ISO date
      def parse_au_date(date_str)
        return nil if date_str.nil? || date_str.empty?

        # Try "5 May 1957" format
        match = date_str.match(/(\d{1,2})\s+(\w+)\s+(\d{4})/)
        if match
          day = match[1].rjust(2, '0')
          month_name = match[2]
          year = match[3]

          months = %w[January February March April May June July August September October November December]
          month = (months.index(month_name) || 0) + 1
          month = month.to_s.rjust(2, '0')

          return "#{year}-#{month}-#{day}"
        end

        # Try "April 1957" format (month/year only)
        match = date_str.match(/(\w+)\s+(\d{4})/)
        if match
          month_name = match[1]
          year = match[2]

          months = %w[January February March April May June July August September October November December]
          month = (months.index(month_name) || 0) + 1
          month = month.to_s.rjust(2, '0')

          return "#{year}-#{month}"
        end

        # Try "2/2/26" format (M/D/YY)
        match = date_str.match(/(\d{1,2})\/(\d{1,2})\/(\d{2,4})/)
        if match
          month = match[1].rjust(2, '0')
          day = match[2].rjust(2, '0')
          year = match[3]
          year = "20#{year}" if year.length == 2

          return "#{year}-#{month}-#{day}"
        end

        nil
      end

      # Map regime to code
      # @param regime [String]
      # @return [String]
      def regime_code(regime)
        return 'AU' unless regime

        case regime.downcase
        when /afghanistan/i then 'AFGHANISTAN'
        when /dprk|korea/i then 'DPRK'
        when /iran/i then 'IRAN'
        when /russia/i then 'RUSSIA'
        when /syria/i then 'SYRIA'
        when /vessels/i then 'VESSELS'
        else regime.upcase.gsub(/[^A-Z0-9_]/, '_')[0..20]
        end
      end
    end
  end
end

# Register the extractor
Ammitto::Extractors::Registry.register(:au, Ammitto::Extractors::AuExtractor)
