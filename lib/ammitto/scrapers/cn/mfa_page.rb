# frozen_string_literal: true

require_relative '../base_page'

module Ammitto
  module Scrapers
    module Cn
      # MfaPage scrapes China's Ministry of Foreign Affairs (MFA) sanctions
      # announcements
      #
      # MFA maintains:
      # 1. 反制裁清单 (Anti-Sanctions List)
      #
      # Source: https://www.mfa.gov.cn
      #
      # @example Scraping MFA announcements
      #   scraper = Ammitto::Scrapers::Cn::MfaPage.new(verbose: true)
      #   announcements = scraper.fetch_and_parse
      #
      class MfaPage < BasePage
        # MFA sanctions list URLs
        # Note: These URLs may change. Check MFA website for current locations.
        ANTI_SANCTIONS_URL = 'https://www.mfa.gov.cn/web/wjdt_674879/zcyj_674883/'

        # List type identifier
        LIST_TYPE = 'anti_sanctions'

        # Initialize with options
        # @param options [Hash] scraper options
        def initialize(options = {})
          super(options)
        end

        # The URL to scrape
        # @return [String]
        def url
          ANTI_SANCTIONS_URL
        end

        # Parse the MFA page
        # @return [Array<Hash>] array of announcement data
        def parse
          return [] unless @page

          # Find and parse announcement links
          links = find_announcement_links
          announcements = []

          links.first(5).each do |link_info| # Limit for testing
            announcement = fetch_and_parse_announcement(link_info[:url])
            announcements << announcement if announcement
          rescue StandardError => e
            puts "[MfaPage] Error parsing #{link_info[:url]}: #{e.message}" if verbose?
          end

          announcements
        end

        # Fetch and parse all announcements
        # @return [Array<Hash>]
        def fetch_all_announcements
          fetch
          parse
        end

        private

        # Find announcement links from the index page
        # @return [Array<Hash>]
        def find_announcement_links
          links = []

          # MFA typically uses list structures
          @page.links.each do |link|
            href = link.href
            text = link.text

            next unless href && text
            next unless anti_sanctions_link?(text, href)

            full_url = @page.uri.merge(href).to_s

            links << {
              url: full_url,
              title: text.strip,
              date: extract_date_from_url(href) || extract_date_from_text(text)
            }
          end

          links
        end

        # Check if link is an anti-sanctions announcement
        # @param text [String]
        # @param href [String]
        # @return [Boolean]
        def anti_sanctions_link?(text, href)
          text.include?('反制裁') ||
            text.include?('制裁清单') ||
            href.include?('fanzhicai')
        end

        # Extract date from URL path
        # @param url [String]
        # @return [String, nil]
        def extract_date_from_url(url)
          # Look for date patterns in URL
          match = url.match(/(\d{4})(\d{2})(\d{2})/)
          return "#{match[1]}-#{match[2]}-#{match[3]}" if match

          match = url.match(%r{(\d{4})[-_/](\d{2})[-_/](\d{2})})
          return "#{match[1]}-#{match[2]}-#{match[3]}" if match

          nil
        end

        # Extract date from text
        # @param text [String]
        # @return [String, nil]
        def extract_date_from_text(text)
          parse_chinese_date(text)
        end

        # Fetch and parse an individual announcement
        # @param url [String]
        # @return [Hash, nil]
        def fetch_and_parse_announcement(url)
          puts "[MfaPage] Fetching announcement: #{url}" if verbose?

          begin
            detail_page = @agent.get(url)
          rescue StandardError => e
            puts "[MfaPage] Error fetching #{url}: #{e.message}" if verbose?
            return nil
          end

          parse_announcement_detail(detail_page, url)
        end

        # Parse announcement detail page
        # @param page [Mechanize::Page]
        # @param url [String]
        # @return [Hash, nil]
        def parse_announcement_detail(page, url)
          # Find content area
          content = page.search('.content, article, #content, .newscontent').first
          content ||= page.search('body').first

          return nil unless content

          text = content.text

          # Parse announcement details
          {
            list_type: LIST_TYPE,
            source_url: url,
            announcement_number: extract_announcement_number(text),
            date: extract_announcement_date(text),
            title: extract_title(page),
            reason: extract_reason_from_text(text),
            measures: extract_measures_from_text(text),
            entities: extract_entities_from_text(text)
          }
        end

        # Extract announcement number
        # @param text [String]
        # @return [String, nil]
        def extract_announcement_number(text)
          # Pattern: 第X号
          match = text.match(/第(\d+)号/)
          return "第#{match[1]}号" if match

          nil
        end

        # Extract announcement date
        # @param text [String]
        # @return [String, nil]
        def extract_announcement_date(text)
          parse_chinese_date(text)
        end

        # Extract title from page
        # @param page [Mechanize::Page]
        # @return [String, nil]
        def extract_title(page)
          title_node = page.search('h1, .title, #title').first
          extract_text(title_node)
        end

        # Extract sanctioned entities
        # @param text [String]
        # @return [Array<Hash>]
        def extract_entities_from_text(text)
          entities = []

          # MFA announcements often list entities/persons with both
          # Chinese and English names

          # Pattern 1: Numbered list
          # 一、对下列人员实施制裁：
          # 1. 中文姓名 (English Name)，职务/Title

          # Pattern 2: Company entities
          # 二、对下列实体实施制裁：
          # 1. 中文公司名 (English Company Name)

          current_entity_type = nil

          text.each_line do |line|
            # Check for entity type headers
            if line.include?('人员') || line.include?('个人')
              current_entity_type = 'person'
            elsif line.include?('实体') || line.include?('机构')
              current_entity_type = 'organization'
            end

            # Extract entities from line
            # Pattern: 1. 中文 (English)
            match = line.match(/^\s*(\d+)\.\s*(.+?)\s*[（(]\s*(.+?)\s*[)）]/)
            next unless match

            name_info = extract_bilingual_name("#{match[2]} (#{match[3]})")

            # Check for title after name
            title_match = match.post_match&.match(/[，,]\s*(.+?)(?:[，,。\n]|$)/)
            title = title_match ? clean_chinese_text(title_match[1]) : nil

            entities << {
              index: match[0].to_i,
              chinese_name: name_info[:chinese_name],
              english_name: name_info[:english_name],
              entity_type: current_entity_type || detect_entity_type(match[2]),
              title: title
            }
          end

          entities
        end

        # Detect if entity is person or organization based on name
        # @param name [String]
        # @return [String] 'person' or 'organization'
        def detect_entity_type(name)
          # Organization keywords
          return 'organization' if name.match?(/公司|企业|集团|有限|责任|股份|银行|基金|协会|中心/)

          # Default to person for names without organization keywords
          'person'
        end

        # Extract measures from text
        # @param text [String]
        # @return [Array<String>]
        def extract_measures_from_text(text)
          measures = []

          # Common MFA sanction measures
          measure_patterns = [
            /禁止[^。]+入境/,
            /冻结[^。]+财产/,
            /禁止[^。]+交易/,
            /不予签发签证/
          ]

          measure_patterns.each do |pattern|
            text.scan(pattern).each do |match|
              measures << clean_chinese_text(match)
            end
          end

          measures.uniq
        end

        # Extract reason from text
        # @param text [String]
        # @return [String, nil]
        def extract_reason_from_text(text)
          # Look for reason patterns
          match = text.match(/决定[对将][^。]+实施[^。]+[。为]/)
          return clean_chinese_text(match[0]) if match

          # Alternative pattern
          match = text.match(/鉴于[^。]+[，。]/)
          return clean_chinese_text(match[0]) if match

          nil
        end
      end
    end
  end
end
