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
    # Data is read from local reference documents in data-cn/reference-docs/
    # or can be fetched via web scraping if reference docs are not available.
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

      # @return [String] API endpoint
      def api_endpoint
        'https://www.mofcom.gov.cn'
      end

      # @return [String, nil] path to reference docs
      attr_accessor :reference_docs_path

      # Fetch raw data from China sources
      # Uses local reference docs if available, otherwise web scraping
      # @return [Hash] { announcements: [...], entities: [...], errors: [...] }
      def fetch
        # Try local reference docs first
        if reference_docs_path && Dir.exist?(reference_docs_path)
          puts "[#{code}] Fetching China sanctions from local reference docs..." if verbose?
          return refuse_empty_harvest(fetch_from_reference_docs)
        end

        # Fall back to web scraping
        puts "[#{code}] Fetching China sanctions via web scraping..." if verbose?
        fetch_from_web
      end

      # Fetch from local reference documents
      # @return [Hash]
      def fetch_from_reference_docs
        require_relative '../sources/cn/reference_docs_parser'

        parser = Ammitto::Sources::Cn::ReferenceDocsParser.new(
          reference_docs_path,
          verbose: verbose?
        )

        @fetched_data = parser.parse_all

        puts "[#{code}] Parsed #{@fetched_data[:entities].length} entities from reference docs" if verbose?

        @fetched_data
      end

      # Fetch via web scraping (fallback)
      # @return [Hash]
      def fetch_from_web
        require_relative '../scrapers/cn/cn_sanctions_scraper'

        scraper = Ammitto::Scrapers::Cn::CnSanctionsScraper.new(
          verbose: verbose?,
          mofcom: true,
          mfa: true
        )

        @fetched_data = scraper.fetch_all

        # Refuse rather than report an empty harvest as a success. The
        # scraper collects per-source errors instead of raising, so a
        # blocked or restructured site arrives here as {entities: [],
        # errors: [...]} — and a caller reading only :entities concludes
        # China sanctions nobody. RuExtractor already makes both checks;
        # this is the same refusal.
        errors = @fetched_data[:errors] || []
        unless errors.empty?
          details = errors.map { |e| "#{e[:source]}: #{e[:error]}" }
          # Ammitto::Error, not NetworkError: the scraper's boundaries
          # rescue StandardError, so this list can hold parse failures as
          # well as fetch failures. Calling a mixed set "network" tells a
          # caller to retry when the site's format may simply have
          # changed. No :url either — it spans MOFCOM's two lists and MFA.
          raise Ammitto::Error,
                "cn scrape failed: #{details.join('; ')}"
        end

        if (@fetched_data[:entities] || []).empty?
          raise Ammitto::ParseError.new(
            'cn scrape yielded zero entities: the site is blocked or its ' \
            'structure changed; refusing to report success', format: :html
          )
        end

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

      # Refuse a harvest that found nothing, whichever route produced it.
      #
      # The web route makes this check inline. The reference-docs route
      # returned straight to the caller, so an empty or unreadable
      # directory produced {announcements: [], entities: []} and then
      # {status: :success, entities: 0} — the same false negative the web
      # route was fixed to stop making.
      #
      # @param data [Hash] a fetch result
      # @return [Hash] the same result when it holds entities
      # @raise [Ammitto::ParseError] when it holds none
      def refuse_empty_harvest(data)
        errors = data[:errors] || []
        unless errors.empty?
          details = errors.map { |e| "#{e[:source]}: #{e[:error]}" }
          raise Ammitto::ParseError.new(
            "cn reference docs failed: #{details.join('; ')}", format: :yaml
          )
        end

        if (data[:entities] || []).empty?
          raise Ammitto::ParseError.new(
            'cn reference docs yielded zero entities: the directory is ' \
            'empty, unreadable, or contained no extractable entities; ' \
            'refusing to report success', format: :yaml
          )
        end

        data
      end

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
        if measures.nil? || measures.empty?
          return [{ '@type' => 'SanctionEffect', 'effectType' => 'sectoral_sanction',
                    'scope' => 'full' }]
        end

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
    end
  end
end

# Register the extractor
Ammitto::Extractors::Registry.register(:cn, Ammitto::Extractors::CnExtractor)
