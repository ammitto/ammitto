# frozen_string_literal: true

require_relative 'base_extractor'
require_relative 'registry'

module Ammitto
  module Extractors
    # RuExtractor extracts sanctions data from Russia (MID/CBR)
    #
    # Russia maintains:
    # 1. Стоп-лист (Stop-list) - Entry bans on foreign persons
    # 2. Central Bank sanctions
    # 3. Government decrees (Постановления)
    #
    # Data is published as HTML announcements from Ministry of Foreign Affairs (MID).
    # This extractor uses web scraping to fetch and parse the data.
    #
    # Source URL: mid.ru
    #
    class RuExtractor < BaseExtractor
      # @return [Symbol] the source code
      def code
        :ru
      end

      # @return [String] authority name
      def authority_name
        'Russia (MID/CBR)'
      end

      # @return [String] API endpoint (uses web scraping)
      def api_endpoint
        'https://www.mid.ru'
      end

      # Fetch raw data from Russia sources
      # Uses web scraping to fetch HTML announcements
      # @return [Hash] { announcements: [...], entities: [...], errors: [...] }
      def fetch
        puts "[#{code}] Fetching Russia sanctions data via web scraping..." if verbose?

        require_relative '../scrapers/ru/ru_sanctions_scraper'

        scraper = Ammitto::Scrapers::Ru::RuSanctionsScraper.new(
          verbose: verbose?,
          mid: true
        )

        @fetched_data = scraper.fetch_all

        puts "[#{code}] Fetched #{@fetched_data[:entities].length} entities" if verbose?

        @fetched_data
      end

      # Extract entities from Russia data
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

      # Extract sanction entries from Russia data
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
        return nil unless data[:russian_name] || data[:english_name]

        entity_id = generate_entity_id(code, create_reference(data))

        {
          '@id' => entity_id,
          '@type' => data[:entity_type] == 'person' ? 'PersonEntity' : 'OrganizationEntity',
          'entityType' => data[:entity_type] || 'person',
          'names' => build_names(data),
          'sourceReferences' => [{
            '@type' => 'SourceReference',
            'sourceCode' => 'ru',
            'referenceNumber' => create_reference(data)
          }],
          'remarks' => build_remarks(data)
        }
      end

      # Build sanction entry hash from parsed data
      # @param data [Hash] parsed entity data
      # @return [Hash]
      def build_entry_hash(data)
        return nil unless data[:russian_name] || data[:english_name]

        entity_id = generate_entity_id(code, create_reference(data))
        entry_id = generate_entry_id(code, create_reference(data))

        {
          '@id' => entry_id,
          '@type' => 'SanctionEntry',
          'entityId' => entity_id,
          'authority' => {
            '@type' => 'Authority',
            'id' => 'ru',
            'name' => 'Russia',
            'countryCode' => 'RU'
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
              'ru:list_type' => data[:list_type],
              'ru:announcement_number' => data[:announcement_number],
              'ru:announcement_date' => data[:announcement_date],
              'ru:russian_name' => data[:russian_name],
              'ru:title' => data[:title],
              'ru:source_url' => data[:source_url]
            }.compact
          }
        }
      end

      # Create a reference number for the entity
      # @param data [Hash]
      # @return [String]
      def create_reference(data)
        base = data[:announcement_number] || 'RU'
        name = data[:english_name] || data[:russian_name] || 'unknown'
        sanitized_name = name.to_s.gsub(/[^a-zA-Z0-9\u0400-\u04FF]/, '-')[0..30]
        "#{base}-#{sanitized_name}"
      end

      # Build names array from entity data
      # @param data [Hash]
      # @return [Array<Hash>]
      def build_names(data)
        names = []

        # Russian name (Cyrillic)
        if data[:russian_name] && !data[:russian_name].empty?
          names << {
            '@type' => 'NameVariant',
            'fullName' => data[:russian_name],
            'script' => 'Cyrl',
            'isPrimary' => data[:english_name].nil? || data[:english_name].empty?
          }
        end

        # English name (Latin)
        if data[:english_name] && !data[:english_name].empty?
          names << {
            '@type' => 'NameVariant',
            'fullName' => data[:english_name],
            'script' => 'Latn',
            'isPrimary' => true
          }
        end

        names
      end

      # Build effects array from measures
      # @param measures [Array<String>]
      # @return [Array<Hash>]
      def build_effects(measures)
        return [{ '@type' => 'SanctionEffect', 'effectType' => 'entry_ban', 'scope' => 'full' }] if measures.nil? || measures.empty?

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
        when /въезд/, /entry.*ban/i
          'entry_ban'
        when /замораживан.*актив/, /asset.*freeze/i
          'asset_freeze'
        when /ограничен.*финансов/, /financial.*restriction/i
          'financial_restriction'
        when /запрет.*сделок/, /transaction.*ban/i
          'transaction_ban'
        else
          'sectoral_sanction'
        end
      end

      # Map list type to display name
      # @param list_type [String]
      # @return [String]
      def map_list_type_to_name(list_type)
        case list_type
        when 'stop_list'
          'Стоп-лист (Stop-list)'
        when 'financial_sanctions'
          'Финансовые санкции (Financial Sanctions)'
        when 'government_decree'
          'Постановления (Government Decrees)'
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
Ammitto::Extractors::Registry.register(:ru, Ammitto::Extractors::RuExtractor)
