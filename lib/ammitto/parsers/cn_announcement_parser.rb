# frozen_string_literal: true

require 'nokogiri'

module Ammitto
  module Parsers
    # CnAnnouncementParser parses China MOFCOM sanctions announcements
    #
    # This parser handles the "不可靠实体清单" (Unreliable Entity List) announcements
    # from China's Ministry of Commerce.
    #
    # The announcements contain:
    # - List of sanctioned entities (companies) with Chinese and English names
    # - Measures imposed (import/export ban, investment ban, etc.)
    # - Legal basis references
    #
    # @example
    #   parser = Ammitto::Parsers::CnAnnouncementParser.new(content)
    #   entities = parser.parse
    #   # => [{ name: "Lockheed Martin", name_cn: "洛克希德·马丁", ... }]
    #
    class CnAnnouncementParser
      # Measures that can be imposed
      MEASURES = {
        '禁止从事与中国有关的进出口活动' => 'import_export_ban',
        '禁止在中国境内新增投资' => 'investment_ban',
        '禁止高级管理人员入境' => 'entry_ban',
        '不批准并取消高级管理人员工作许可' => 'work_permit_ban',
        '查封、扣押、冻结在中国境内的各类财产' => 'asset_freeze',
        '禁止中国境内的组织、个人与其进行有关交易' => 'transaction_ban'
      }.freeze

      # List types
      LIST_TYPES = {
        '不可靠实体清单' => 'unreliable_entity',
        '反制裁' => 'anti_sanctions',
        '出口管制' => 'export_control'
      }.freeze

      # @return [String] the announcement content
      attr_reader :content

      # Initialize with announcement content
      # @param content [String] the markdown/text content
      def initialize(content)
        @content = content
      end

      # Parse the announcement and extract entities
      # @return [Array<Hash>] array of entity hashes
      def parse
        entities = []

        # Extract metadata
        metadata = extract_metadata

        # Detect list type
        list_type = detect_list_type

        # Extract entities from the announcement
        entity_names = extract_entity_names

        # Extract measures
        measures = extract_measures

        entity_names.each_with_index do |entity, index|
          entities << {
            id: generate_id(entity[:english], index),
            name: entity[:english],
            name_cn: entity[:chinese],
            list_type: list_type,
            measures: measures,
            announcement_date: metadata[:date],
            announcement_number: metadata[:number],
            issuing_authority: metadata[:authority],
            legal_basis: extract_legal_basis,
            source: 'cn'
          }
        end

        entities
      end

      private

      # Extract metadata from announcement header
      # @return [Hash]
      def extract_metadata
        {
          authority: extract_field('【发布单位】'),
          number: extract_field('【发布文号】'),
          date: parse_date(extract_field('【发文日期】'))
        }
      end

      # Extract a specific field from the content
      # @param field_name [String] the field name to extract
      # @return [String, nil]
      def extract_field(field_name)
        match = content.match(/#{Regexp.escape(field_name)}(.*)/)
        match[1].strip if match
      end

      # Parse date from Chinese format
      # @param date_str [String] date string like "2025年01月14日"
      # @return [Date, nil]
      def parse_date(date_str)
        return nil unless date_str

        match = date_str.match(/(\d{4})年(\d{2})月(\d{2})日/)
        return nil unless match

        Date.new(match[1].to_i, match[2].to_i, match[3].to_i)
      rescue ArgumentError
        nil
      end

      # Detect the type of sanctions list
      # @return [String]
      def detect_list_type
        LIST_TYPES.each do |keyword, type|
          return type if content.include?(keyword)
        end
        'unknown'
      end

      # Extract entity names from the announcement
      # @return [Array<Hash>] array with :chinese and :english keys
      def extract_entity_names
        entities = []

        # Pattern: Chinese name followed by English name in parentheses
        # e.g., 洛克希德·马丁导弹与火控公司（Lockheed Martin Missiles and Fire Control）
        pattern = /([^（(]+?)（([^）)]+)）/

        content.scan(pattern) do |match|
          chinese_name = match[0].strip
          english_name = match[1].strip

          # Skip if this looks like a date or metadata
          next if chinese_name.match?(/\d{4}年/)
          next if english_name.match?(/^\d+$/)

          entities << {
            chinese: chinese_name,
            english: english_name
          }
        end

        entities
      end

      # Extract measures from the announcement
      # @return [Array<String>]
      def extract_measures
        measures = []

        MEASURES.each do |chinese, english|
          if content.include?(chinese)
            measures << english
          end
        end

        measures
      end

      # Extract legal basis references
      # @return [Array<String>]
      def extract_legal_basis
        bases = []

        if content.include?('《中华人民共和国对外贸易法》')
          bases << 'Foreign Trade Law of the PRC'
        end
        if content.include?('《中华人民共和国国家安全法》')
          bases << 'National Security Law of the PRC'
        end
        if content.include?('《中华人民共和国反外国制裁法》')
          bases << 'Anti-Foreign Sanctions Law of the PRC'
        end
        if content.include?('《不可靠实体清单规定》')
          bases << 'Unreliable Entity List Provisions'
        end

        bases
      end

      # Generate a unique ID for an entity
      # @param english_name [String]
      # @param index [Integer]
      # @return [String]
      def generate_id(english_name, index)
        # Create a slug from the English name
        slug = english_name
                 .downcase
                 .gsub(/[^a-z0-9]+/, '-')
                 .gsub(/^-|-$/, '')
                 .slice(0, 50)

        "cn-#{slug}-#{index}"
      end
    end
  end
end
