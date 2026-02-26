# frozen_string_literal: true

require_relative '../base_page'

module Ammitto
  module Scrapers
    module Cn
      # MofcomPage scrapes China's Ministry of Commerce (MOFCOM) sanctions
      # announcements
      #
      # MOFCOM maintains:
      # 1. 不可靠实体清单 (Unreliable Entity List)
      # 2. 出口管制管控名单 (Export Control List)
      #
      # Source: https://www.mofcom.gov.cn
      #
      # @example Scraping MOFCOM announcements
      #   scraper = Ammitto::Scrapers::Cn::MofcomPage.new(verbose: true)
      #   announcements = scraper.fetch_and_parse
      #
      class MofcomPage < BasePage
        # MOFCOM sanctions list URLs
        # Note: These URLs may change. Check MOFCOM website for current locations.
        UNRELIABLE_ENTITY_LIST_URL = 'https://www.mofcom.gov.cn/zcfb/zcfbzgml/col/col2021030312.html'
        EXPORT_CONTROL_LIST_URL = 'https://www.mofcom.gov.cn/zcfb/zcfbzgml/col/col2021030313.html'

        # List type identifiers
        LIST_TYPES = {
          unreliable_entity: 'unreliable_entity',
          export_control: 'export_control'
        }.freeze

        # Initialize with list type
        # @param list_type [Symbol] :unreliable_entity or :export_control
        # @param options [Hash] scraper options
        def initialize(list_type: :unreliable_entity, options: {})
          super(options)
          @list_type = list_type
        end

        # The URL to scrape based on list type
        # @return [String]
        def url
          case @list_type
          when :export_control
            EXPORT_CONTROL_LIST_URL
          else
            UNRELIABLE_ENTITY_LIST_URL
          end
        end

        # Parse the MOFCOM page
        # @return [Array<Hash>] array of announcement data
        def parse
          return [] unless @page

          announcements = []

          # Find announcement links
          # MOFCOM typically has a list of links to individual announcements
          announcement_links = find_announcement_links

          announcement_links.each do |link_info|
            announcement = parse_announcement(link_info)
            announcements << announcement if announcement
          end

          announcements
        end

        # Fetch and parse all announcements from MOFCOM
        # @return [Array<Hash>] array of parsed announcements
        def fetch_all_announcements
          announcements = []

          # First, fetch the index page
          fetch
          return announcements unless @page

          # Find and follow links to individual announcements
          links = find_announcement_links

          links.first(5).each do |link_info| # Limit to first 5 for testing
            announcement = fetch_and_parse_announcement(link_info[:url])
            announcements << announcement if announcement
          rescue StandardError => e
            puts "[MofcomPage] Error parsing #{link_info[:url]}: #{e.message}" if verbose?
          end

          announcements
        end

        private

        # Find announcement links from the index page
        # @return [Array<Hash>] array of { url:, title:, date: }
        def find_announcement_links
          links = []

          # MOFCOM typically uses list structures with links
          # This selector may need adjustment based on actual page structure
          @page.search('a[href*="/art/"]').each do |link|
            href = link['href']
            title = extract_text(link)
            next unless href && title

            # Filter for announcement-like titles
            next unless announcement_title?(title)

            # Resolve relative URLs
            full_url = @page.uri.merge(href).to_s

            links << {
              url: full_url,
              title: title,
              date: extract_date_from_text(title) || extract_date_near_link(link)
            }
          end

          links
        end

        # Check if title looks like a sanctions announcement
        # @param title [String]
        # @return [Boolean]
        def announcement_title?(title)
          title.include?('公告') ||
            title.include?('不可靠实体清单') ||
            title.include?('出口管制') ||
            title.include?('制裁')
        end

        # Extract date from text (Chinese or ISO format)
        # @param text [String]
        # @return [String, nil] ISO date
        def extract_date_from_text(text)
          parse_chinese_date(text)
        end

        # Extract date near a link element
        # @param link [Nokogiri::XML::Node]
        # @return [String, nil] ISO date
        def extract_date_near_link(link)
          # Check sibling/parent elements for date
          parent = link.parent
          return nil unless parent

          parent.text.scan(%r{\d{4}[-/年]\d{1,2}[-/月]\d{1,2}日?}).first
        end

        # Parse announcement link info
        # @param link_info [Hash]
        # @return [Hash, nil]
        def parse_announcement(link_info)
          {
            list_type: LIST_TYPES[@list_type],
            source_url: link_info[:url],
            title: link_info[:title],
            date: link_info[:date],
            entities: [] # Will be populated when fetching detail page
          }
        end

        # Fetch and parse an individual announcement page
        # @param announcement_url [String]
        # @return [Hash, nil]
        def fetch_and_parse_announcement(announcement_url)
          puts "[MofcomPage] Fetching announcement: #{announcement_url}" if verbose?

          begin
            detail_page = @agent.get(announcement_url)
          rescue StandardError => e
            puts "[MofcomPage] Error fetching #{announcement_url}: #{e.message}" if verbose?
            return nil
          end

          parse_announcement_detail(detail_page, announcement_url)
        end

        # Parse an individual announcement page
        # @param page [Mechanize::Page]
        # @param url [String] the announcement URL
        # @return [Hash, nil]
        def parse_announcement_detail(page, url)
          content = page.search('.TRS_Editor, .content, article, #content').first
          content ||= page.search('body').first

          return nil unless content

          text = content.text

          # Extract announcement number
          announcement_number = extract_announcement_number(text)

          # Extract date
          date = extract_announcement_date(text)

          # Extract entities from the announcement
          entities = extract_entities_from_text(text)

          # Extract measures/effects
          measures = extract_measures_from_text(text)

          # Extract legal basis
          legal_basis = extract_legal_basis_from_text(text)

          # Extract reason
          reason = extract_reason_from_text(text)

          {
            list_type: LIST_TYPES[@list_type],
            source_url: url,
            announcement_number: announcement_number,
            date: date,
            legal_basis: legal_basis,
            reason: reason,
            measures: measures,
            entities: entities
          }
        end

        # Extract announcement number from text
        # @param text [String]
        # @return [String, nil]
        def extract_announcement_number(text)
          # Pattern: 公告 2025年 第5号 or 商务部令2025年第5号
          match = text.match(/(?:公告|令)\s*(\d{4})年?\s*第?(\d+)号/)
          return "#{match[1]}年 第#{match[2]}号" if match

          nil
        end

        # Extract announcement date from text
        # @param text [String]
        # @return [String, nil] ISO date
        def extract_announcement_date(text)
          parse_chinese_date(text)
        end

        # Extract sanctioned entities from announcement text
        # @param text [String]
        # @return [Array<Hash>]
        def extract_entities_from_text(text)
          entities = []

          # Look for entity names in the announcement
          # Entities are often listed after phrases like "附件：" or "被列入...的实体："

          # Pattern 1: Numbered list with Chinese and English names
          # 1. 中文公司名 (English Company Name)
          text.scan(/^\s*(\d+)\.\s*(.+?)\s*[（(]\s*(.+?)\s*[)）]/m).each do |match|
            entities << {
              index: match[0].to_i,
              chinese_name: clean_chinese_text(match[1]),
              english_name: match[2]&.strip,
              entity_type: 'organization'
            }
          end

          # Pattern 2: Simple list with Chinese names
          if entities.empty?
            text.scan(/^\s*(\d+)\.\s*(.+?)(?=\n\s*\d+\.|\n\s*$|\n\s*附件)/m).each do |match|
              name = clean_chinese_text(match[1])
              next if name.nil? || name.length < 2

              # Check if it looks like a company name
              next unless name.match?(/公司|企业|集团|有限|责任|股份/)

              entities << {
                index: match[0].to_i,
                chinese_name: name,
                english_name: nil,
                entity_type: 'organization'
              }
            end
          end

          entities
        end

        # Extract sanction measures from text
        # @param text [String]
        # @return [Array<String>]
        def extract_measures_from_text(text)
          measures = []

          # Look for numbered measures
          # 1. 禁止...
          # 2. 禁止...
          text.scan(/^\s*(\d+)\.\s*(禁止.+?)$/m).each do |match|
            measure = clean_chinese_text(match[1])
            measures << measure if measure
          end

          # Look for common measure patterns
          if measures.empty?
            measure_patterns = [
              /禁止[^。]+从事[^。]+活动/,
              /禁止[^。]+投资/,
              /禁止[^。]+进出口/,
              /冻结[^。]+财产/
            ]

            measure_patterns.each do |pattern|
              text.scan(pattern).each do |match|
                measures << clean_chinese_text(match)
              end
            end
          end

          measures.uniq
        end

        # Extract legal basis from text
        # @param text [String]
        # @return [Array<String>]
        def extract_legal_basis_from_text(text)
          basis = []

          # Look for law references
          law_patterns = [
            '《中华人民共和国对外贸易法》',
            '《中华人民共和国国家安全法》',
            '《中华人民共和国反外国制裁法》',
            '《不可靠实体清单规定》'
          ]

          law_patterns.each do |law|
            basis << law if text.include?(law)
          end

          basis
        end

        # Extract reason from text
        # @param text [String]
        # @return [String, nil]
        def extract_reason_from_text(text)
          # Look for reason patterns
          match = text.match(/为[^，。]+[，。]/)
          return clean_chinese_text(match[0]) if match

          nil
        end
      end
    end
  end
end
