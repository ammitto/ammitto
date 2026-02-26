# frozen_string_literal: true

require_relative 'base_extractor'
require_relative 'registry'

module Ammitto
  module Extractors
    # CnExtractor extracts sanctions data from China (MOFCOM/MFA)
    #
    # China has multiple sanctions lists:
    # 1. 不可靠实体清单 (Unreliable Entity List) - MOFCOM
    # 2. 反制裁清单 (Anti-Sanctions List) - MFA
    # 3. 出口管制管控名单 (Export Control List) - MOFCOM
    #
    # Data is published as HTML announcements, not structured XML/JSON.
    # This extractor uses web scraping to fetch and parse the data.
    #
    # Source URLs:
    # - mofcom.gov.cn (商务部)
    # - mfa.gov.cn (外交部)
    #
    class CnExtractor < BaseExtractor
      # @return [Symbol] the source code
      def code
        :cn
      end

      # @return [String] authority name
      def authority_name
        'China (MOFCOM/MFA)'
      end

      # @return [String] API endpoint (uses web scraping)
      def api_endpoint
        'https://www.mofcom.gov.cn'
      end

      # Fetch raw data from China sources
      # Uses web scraping to fetch HTML announcements
      # @return [Hash] { announcements: [...], entities: [...], errors: [...] }
      def fetch
        puts "[#{code}] Fetching China sanctions data via web scraping..." if verbose?

        require_relative '../scrapers/cn/cn_sanctions_scraper'

        scraper = Ammitto::Scrapers::Cn::CnSanctionsScraper.new(
          verbose: verbose?,
          mofcom: true,
          mfa: true
        )

        @fetched_data = scraper.fetch_all

        puts "[#{code}] Fetched #{@fetched_data[:entities].length} entities" if verbose?

        @fetched_data
      end

      # Extract entities from China data
      # @param data [Hash, nil] fetched data (uses @fetched_data if nil)
      # @return [Array<Hash>]
      def extract_entities(data = nil)
        data ||= @fetched_data
        return [] unless data

        entities = data[:entities] || []

        entities.map do |entity_data|
          build_entity_hash(entity_data)
        end.compact
      end

      # Extract sanction entries from China data
      # @param data [Hash, nil] fetched data (uses @fetched_data if nil)
      # @return [Array<Hash>]
      def extract_entries(data = nil)
        data ||= @fetched_data
        return [] unless data

        entities = data[:entities] || []

        entities.map do |entity_data|
          build_entry_hash(entity_data)
        end.compact
      end

      private

      # Build entity hash from parsed data
      # @param data [Hash] parsed entity data
      # @return [Hash]
      def build_entity_hash(data)
        return nil unless data[:chinese_name] || data[:english_name]

        entity_id = generate_entity_id(code, create_reference(data))

        {
          '@id' => entity_id,
          '@type' => data[:entity_type] == 'person' ? 'PersonEntity' : 'OrganizationEntity',
          'entityType' => data[:entity_type] || 'organization',
          'names' => build_names(data),
          'sourceReferences' => [{
            '@type' => 'SourceReference',
            'sourceCode' => 'cn',
            'referenceNumber' => create_reference(data)
          }],
          'remarks' => build_remarks(data)
        }
      end

      # Build sanction entry hash from parsed data
      # @param data [Hash] parsed entity data
      # @return [Hash]
      def build_entry_hash(data)
        return nil unless data[:chinese_name] || data[:english_name]

        entity_id = generate_entity_id(code, create_reference(data))
        entry_id = generate_entry_id(code, create_reference(data))

        {
          '@id' => entry_id,
          '@type' => 'SanctionEntry',
          'entityId' => entity_id,
          'authority' => {
            '@type' => 'Authority',
            'id' => 'cn',
            'name' => 'China',
            'countryCode' => 'CN'
          },
          'referenceNumber' => create_reference(data),
          'status' => 'active',
          'regime' => {
            '@type' => 'SanctionRegime',
            'name' => map_list_type_to_name(data[:list_type]),
            'code' => data[:list_type].to_s.upcase
          },
          'effects' => build_effects(data[:measures]),
          'period' => build_period(data),
          'rawSourceData' => {
            '@type' => 'RawSourceData',
            'sourceFormat' => 'html',
            'sourceSpecificFields' => {
              'cn:list_type' => data[:list_type],
              'cn:announcement_number' => data[:announcement_number],
              'cn:announcement_date' => data[:announcement_date],
              'cn:chinese_name' => data[:chinese_name],
              'cn:legal_basis' => data[:legal_basis],
              'cn:source_url' => data[:source_url]
            }.compact
          }
        }
      end

      # Create a reference number for the entity
      # @param data [Hash]
      # @return [String]
      def create_reference(data)
        base = data[:announcement_number] || 'CN'
        name = data[:english_name] || data[:chinese_name] || 'unknown'
        sanitized_name = name.to_s.gsub(/[^a-zA-Z0-9\u4e00-\u9fff]/, '-')[0..30]
        "#{base}-#{sanitized_name}"
      end

      # Build names array from entity data
      # @param data [Hash]
      # @return [Array<Hash>]
      def build_names(data)
        names = []

        if data[:english_name] && !data[:english_name].empty?
          names << {
            '@type' => 'NameVariant',
            'fullName' => data[:english_name],
            'script' => 'Latn',
            'isPrimary' => true
          }
        end

        if data[:chinese_name] && !data[:chinese_name].empty?
          names << {
            '@type' => 'NameVariant',
            'fullName' => data[:chinese_name],
            'script' => 'Hani',
            'isPrimary' => data[:english_name].nil? || data[:english_name].empty?
          }
        end

        names
      end

      # Build effects array from measures
      # @param measures [Array<String>]
      # @return [Array<Hash>]
      def build_effects(measures)
        return [{ '@type' => 'SanctionEffect', 'effectType' => 'sectoral_sanction', 'scope' => 'full' }] if measures.nil? || measures.empty?

        measures.map do |measure|
          {
            '@type' => 'SanctionEffect',
            'effectType' => map_measure_to_effect_type(measure),
            'scope' => 'full',
            'description' => measure
          }
        end
      end

      # Map measure text to effect type
      # @param measure [String]
      # @return [String]
      def map_measure_to_effect_type(measure)
        case measure
        when /冻结.*财产/, /asset.*freeze/i
          'asset_freeze'
        when /禁止.*签证/, /禁止.*入境/, /entry.*ban/i
          'entry_ban'
        when /禁止.*交易/, /transaction.*ban/i
          'transaction_ban'
        when /禁止.*进出口/, /import.*export/i
          'trade_restriction'
        when /禁止.*投资/, /investment.*ban/i
          'investment_ban'
        else
          'sectoral_sanction'
        end
      end

      # Map list type to display name
      # @param list_type [String]
      # @return [String]
      def map_list_type_to_name(list_type)
        case list_type
        when 'unreliable_entity'
          '不可靠实体清单 (Unreliable Entity List)'
        when 'anti_sanctions'
          '反制裁清单 (Anti-Sanctions List)'
        when 'export_control'
          '出口管制管控名单 (Export Control List)'
        else
          list_type.to_s
        end
      end

      # Build period from entity data
      # @param data [Hash]
      # @return [Hash, nil]
      def build_period(data)
        return nil unless data[:announcement_date] || data[:effective_date]

        {
          '@type' => 'TemporalPeriod',
          'listedDate' => data[:announcement_date],
          'effectiveDate' => data[:effective_date] || data[:announcement_date]
        }
      end

      # Build remarks from entity data
      # @param data [Hash]
      # @return [String, nil]
      def build_remarks(data)
        parts = []
        parts << "List: #{data[:list_type]}" if data[:list_type]
        parts << "Reason: #{data[:reason]}" if data[:reason]
        parts << "Title: #{data[:title]}" if data[:title]

        parts.empty? ? nil : parts.join('; ')
      end

      # Check if verbose mode is enabled
      # @return [Boolean]
      def verbose?
        @verbose || ENV['AMMITTO_VERBOSE'] == 'true'
      end
    end
  end
end

# Register the extractor
Ammitto::Extractors::Registry.register(:cn, Ammitto::Extractors::CnExtractor)
