# frozen_string_literal: true

require 'mechanize'
require 'nokogiri'

module Ammitto
  module Scrapers
    # BasePage provides common functionality for web scraping
    #
    # Each scraper should inherit from this class and implement:
    # - #url: The URL to scrape
    # - #parse: Parse the page and return structured data
    #
    # @example Creating a scraper
    #   class MofcomPage < BasePage
    #     def url
    #       'https://www.mofcom.gov.cn/...'
    #     end
    #
    #     def parse
    #       # Extract data from page
    #     end
    #   end
    #
    class BasePage
      # @return [Mechanize::Page, nil] the fetched page
      attr_reader :page

      # @return [Hash] scraper options
      attr_reader :options

      # Initialize the scraper
      # @param options [Hash] scraper options
      # @option options [Boolean] :verbose (false) Enable verbose logging
      # @option options [Integer] :timeout (30) Request timeout in seconds
      # @option options [String] :user_agent Custom user agent string
      def initialize(options = {})
        @options = options
        @agent = build_agent
      end

      # Fetch the page
      # @return [Mechanize::Page, nil] the fetched page
      def fetch
        puts "[#{self.class.name}] Fetching #{url}" if verbose?

        @page = @agent.get(url)
        @page
      rescue Mechanize::ResponseCodeError => e
        puts "[#{self.class.name}] Error: #{e.message}" if verbose?
        nil
      rescue StandardError => e
        puts "[#{self.class.name}] Error: #{e.message}" if verbose?
        nil
      end

      # Parse the page - override in subclass
      # @return [Object] parsed data
      def parse
        raise NotImplementedError, 'Subclasses must implement #parse'
      end

      # Fetch and parse in one step
      # @return [Object] parsed data
      def fetch_and_parse
        fetch
        return nil unless @page

        parse
      end

      protected

      # The URL to scrape - override in subclass
      # @return [String]
      def url
        raise NotImplementedError, 'Subclasses must implement #url'
      end

      # Build the Mechanize agent
      # @return [Mechanize]
      def build_agent
        agent = Mechanize.new
        agent.user_agent = options[:user_agent] || default_user_agent
        agent.open_timeout = options[:timeout] || 30
        agent.read_timeout = options[:timeout] || 30
        agent.max_history = 0 # Don't keep history to save memory
        agent
      end

      # Default user agent string
      # @return [String]
      def default_user_agent
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' \
          '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
      end

      # Check if verbose mode is enabled
      # @return [Boolean]
      def verbose?
        options[:verbose] || ENV['AMMITTO_VERBOSE'] == 'true'
      end

      # Extract text from a node, stripping whitespace
      # @param node [Nokogiri::XML::Node, nil]
      # @return [String, nil]
      def extract_text(node)
        return nil unless node

        text = node.text.to_s.strip
        text.empty? ? nil : text
      end

      # Extract attribute value from a node
      # @param node [Nokogiri::XML::Node, nil]
      # @param attr [String, Symbol] attribute name
      # @return [String, nil]
      def extract_attr(node, attr)
        return nil unless node

        value = node[attr.to_s]&.strip
        value&.empty? ? nil : value
      end

      # Clean Chinese text (remove extra whitespace, normalize punctuation)
      # @param text [String, nil]
      # @return [String, nil]
      def clean_chinese_text(text)
        return nil if text.nil? || text.strip.empty?

        text.strip
            .gsub(/\s+/, ' ')
            .gsub(/[[:space:]]+/, ' ')
      end

      # Extract Chinese and English names from bilingual text
      # @param text [String] text like "中文姓名 (English Name)"
      # @return [Hash] { chinese_name:, english_name: }
      def extract_bilingual_name(text)
        return { chinese_name: nil, english_name: nil } if text.nil?

        # Pattern: "中文名 (英文名)" or "中文名（英文名）"
        match = text.match(/^(.+?)\s*[（(]\s*(.+?)\s*[)）]$/)

        if match
          {
            chinese_name: clean_chinese_text(match[1]),
            english_name: match[2]&.strip
          }
        else
          # No English name in parentheses
          { chinese_name: clean_chinese_text(text), english_name: nil }
        end
      end

      # Parse date from Chinese format
      # @param text [String, nil] date text like "2025年1月15日"
      # @return [String, nil] ISO date string (YYYY-MM-DD)
      def parse_chinese_date(text)
        return nil if text.nil? || text.strip.empty?

        # Try Chinese format: 2025年1月15日
        match = text.match(/(\d{4})年(\d{1,2})月(\d{1,2})日/)
        if match
          year = match[1]
          month = match[2].rjust(2, '0')
          day = match[3].rjust(2, '0')
          return "#{year}-#{month}-#{day}"
        end

        # Try ISO format: 2025-01-15
        match = text.match(/(\d{4})-(\d{2})-(\d{2})/)
        return "#{match[1]}-#{match[2]}-#{match[3]}" if match

        # Try slash format: 2025/01/15
        match = text.match(%r{(\d{4})/(\d{2})/(\d{2})})
        return "#{match[1]}-#{match[2]}-#{match[3]}" if match

        nil
      end
    end
  end
end
