# frozen_string_literal: true

require 'mechanize'
require 'nokogiri'

module Ammitto
  module Parsers
    # CnAntiSanctionsScraper fetches and parses China MFA Anti-Sanctions notices
    #
    # This scraper handles the "反制裁清单" (Anti-Sanctions List) from China's
    # Ministry of Foreign Affairs (MFA).
    #
    # Source: https://www.mfa.gov.cn/web/wjb_673085/zfxxgk_674865/gknrlb/fzcqdcs/
    #
    # The page contains links to individual notice pages, each describing
    # counter-sanctions against foreign entities and persons.
    #
    # @example
    #   scraper = Ammitto::Parsers::CnAntiSanctionsScraper.new(verbose: true)
    #   entities = scraper.fetch_and_parse
    #
    class CnAntiSanctionsScraper
      # Index page URL
      INDEX_URL = 'https://www.mfa.gov.cn/web/wjb_673085/zfxxgk_674865/gknrlb/fzcqdcs/'

      # @return [Mechanize] the mechanize agent
      attr_reader :agent

      # @return [Boolean] verbose mode
      attr_reader :verbose

      # Initialize with options
      # @param verbose [Boolean] enable verbose output
      def initialize(verbose: false)
        @verbose = verbose
        @agent = Mechanize.new
        @agent.user_agent_alias = 'Mac Safari'
        @agent.open_timeout = 30
        @agent.read_timeout = 60
      end

      # Fetch and parse all anti-sanctions notices
      # @return [Array<Hash>] array of entity hashes
      def fetch_and_parse
        entities = []

        puts '[CN Anti-Sanctions] Fetching index page...' if verbose

        # Fetch index page
        index_page = agent.get(INDEX_URL)

        # Find all notice links
        notice_links = extract_notice_links(index_page)
        puts "[CN Anti-Sanctions] Found #{notice_links.length} notices" if verbose

        # Fetch and parse each notice
        notice_links.each_with_index do |link, index|
          puts "[CN Anti-Sanctions] Processing notice #{index + 1}/#{notice_links.length}" if verbose

          begin
            notice_entities = fetch_and_parse_notice(link)
            entities.concat(notice_entities)
          rescue StandardError => e
            puts "[CN Anti-Sanctions] Error processing notice: #{e.message}" if verbose
          end

          # Be polite to the server
          sleep 1
        end

        puts "[CN Anti-Sanctions] Extracted #{entities.length} entities" if verbose

        entities
      end

      private

      # Extract notice links from the index page
      # @param page [Mechanize::Page] the index page
      # @return [Array<String>] array of URLs
      def extract_notice_links(page)
        links = []

        page.links.each do |link|
          href = link.href
          next unless href

          # Look for links to notice pages
          next unless href.include?('/web/') && (href.include?('反制') || href.include?('决定'))

          # Make absolute URL
          uri = URI.join(page.uri.to_s, href)
          links << uri.to_s
        end

        links.uniq
      end

      # Fetch and parse a single notice
      # @param url [String] the notice URL
      # @return [Array<Hash>] array of entity hashes
      def fetch_and_parse_notice(url)
        notice_page = agent.get(url)
        content = notice_page.body

        # Parse the notice content
        parser = CnAntiSanctionsNoticeParser.new(content)
        entities = parser.parse

        # Add source URL to each entity
        entities.each do |entity|
          entity[:source_url] = url
        end

        entities
      rescue Mechanize::ResponseCodeError => e
        puts "[CN Anti-Sanctions] HTTP error: #{e.response_code}" if verbose
        []
      end
    end

    # CnAntiSanctionsNoticeParser parses individual MFA anti-sanctions notices
    #
    class CnAntiSanctionsNoticeParser
      # @return [String] the notice content
      attr_reader :content

      # Initialize with notice content
      # @param content [String] HTML content
      def initialize(content)
        @content = content
      end

      # Parse the notice and extract entities
      # @return [Array<Hash>] array of entity hashes
      def parse
        entities = []

        # Parse HTML
        doc = Nokogiri::HTML(content)

        # Extract title
        title = doc.at('title')&.text || ''

        # Extract main content
        body = doc.at('//div[contains(@class, "content")]') ||
               doc.at('//div[contains(@id, "content")]') ||
               doc.at('body')

        return entities unless body

        text = body.text

        # Extract date
        date = extract_date(text)

        # Extract entity names
        entity_names = extract_entity_names(text)

        # Extract measures
        measures = extract_measures(text)

        entity_names.each_with_index do |entity, index|
          entities << {
            id: generate_id(entity[:english] || entity[:chinese], index),
            name: entity[:english],
            name_cn: entity[:chinese],
            list_type: 'anti_sanctions',
            measures: measures,
            announcement_date: date,
            announcement_title: title,
            legal_basis: ['Anti-Foreign Sanctions Law of the PRC'],
            source: 'cn'
          }
        end

        entities
      end

      private

      # Extract date from text
      # @param text [String]
      # @return [Date, nil]
      def extract_date(text)
        # Try various date formats
        patterns = [
          /(\d{4})年(\d{1,2})月(\d{1,2})日/,
          /(\d{4})\.(\d{1,2})\.(\d{1,2})/,
          /(\d{4})-(\d{1,2})-(\d{1,2})/
        ]

        patterns.each do |pattern|
          match = text.match(pattern)
          next unless match

          begin
            return Date.new(match[1].to_i, match[2].to_i, match[3].to_i)
          rescue ArgumentError
            next
          end
        end

        nil
      end

      # Extract entity names from text
      # @param text [String]
      # @return [Array<Hash>]
      def extract_entity_names
        entities = []

        # Pattern: Chinese name followed by English name in parentheses
        pattern = /([^（(]+?)（([^）)]+)）/

        content.scan(pattern) do |match|
          chinese_name = match[0].strip
          english_name = match[1].strip

          # Skip metadata
          next if chinese_name.match?(/\d{4}年/)
          next if english_name.match?(/^\d+$/)

          entities << {
            chinese: chinese_name,
            english: english_name
          }
        end

        # Also look for standalone English names (for US persons)
        english_pattern = /[A-Z][a-z]+(?:\s+[A-Z][a-z]+)+/
        content.scan(english_pattern) do |match|
          # Only add if not already captured
          unless entities.any? { |e| e[:english] == match }
            entities << {
              chinese: nil,
              english: match.strip
            }
          end
        end

        entities
      end

      # Extract measures from text
      # @return [Array<String>]
      def extract_measures(text)
        measures = []

        measures << 'asset_freeze' if text.include?('查封') || text.include?('冻结')
        measures << 'entry_ban' if text.include?('禁止入境') || text.include?('不予签发签证')
        measures << 'transaction_ban' if text.include?('禁止交易')

        measures
      end

      # Generate a unique ID
      # @param name [String]
      # @param index [Integer]
      # @return [String]
      def generate_id(name, index)
        slug = name
               .to_s
               .downcase
               .gsub(/[^a-z0-9]+/, '-')
               .gsub(/^-|-$/, '')
               .slice(0, 50)

        "cn-as-#{slug}-#{index}"
      end
    end
  end
end
