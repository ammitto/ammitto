# frozen_string_literal: true

require_relative '../base_page'

module Ammitto
  module Scrapers
    module Ru
      # MidPage scrapes Russia's Ministry of Foreign Affairs (MID) sanctions
      # announcements
      #
      # MID maintains:
      # 1. Стоп-лист (Stop-list) - Entry bans on foreign persons
      #
      # Source: https://www.mid.ru
      #
      # @example Scraping MID announcements
      #   scraper = Ammitto::Scrapers::Ru::MidPage.new(verbose: true)
      #   announcements = scraper.fetch_all_announcements
      #
      class MidPage < BasePage
        # MID news/announcements URL
        NEWS_URL = 'https://www.mid.ru/ru/foreign_policy/news/'

        # List type identifier
        LIST_TYPE = 'stop_list'

        # Initialize with options
        # @param options [Hash] scraper options
        def initialize(options = {})
          super
        end

        # The URL to scrape
        # @return [String]
        def url
          NEWS_URL
        end

        # Parse the MID page
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
            puts "[MidPage] Error parsing #{link_info[:url]}: #{e.message}" if verbose?
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

          # MID news page has links to individual announcements
          @page.links.each do |link|
            href = link.href
            text = link.text

            next unless href && text
            next unless sanctions_link?(text, href)

            full_url = @page.uri.merge(href).to_s

            links << {
              url: full_url,
              title: text.strip,
              date: extract_date_from_url(href) || extract_date_from_text(text)
            }
          end

          links
        end

        # Check if link is a sanctions announcement
        # @param text [String]
        # @param href [String]
        # @return [Boolean]
        def sanctions_link?(text, _href)
          text.include?('санкци') ||
            text.include?('стоп-лист') ||
            text.include?('персональн') ||
            text.include?('въезд') ||
            text.include?('заявлен')
        end

        # Extract date from URL path
        # @param url [String]
        # @return [String, nil]
        def extract_date_from_url(url)
          # Look for date patterns in URL
          match = url.match(%r{(\d{4})[-_/](\d{2})[-_/](\d{2})})
          return "#{match[1]}-#{match[2]}-#{match[3]}" if match

          # Match /web/guest/2024-01-15 pattern
          match = url.match(/(\d{4})-(\d{2})-(\d{2})/)
          return "#{match[1]}-#{match[2]}-#{match[3]}" if match

          nil
        end

        # Extract date from text
        # @param text [String]
        # @return [String, nil]
        def extract_date_from_text(text)
          parse_russian_date(text)
        end

        # Parse Russian date format
        # @param text [String]
        # @return [String, nil] ISO date
        def parse_russian_date(text)
          return nil if text.nil? || text.empty?

          # Russian months
          months = {
            'января' => '01', 'февраля' => '02', 'марта' => '03',
            'апреля' => '04', 'мая' => '05', 'июня' => '06',
            'июля' => '07', 'августа' => '08', 'сентября' => '09',
            'октября' => '10', 'ноября' => '11', 'декабря' => '12'
          }

          # Pattern: "15 января 2024"
          match = text.match(/(\d{1,2})\s+(#{months.keys.join('|')})\s+(\d{4})/i)
          if match
            day = match[1].rjust(2, '0')
            month = months[match[2].downcase]
            year = match[3]
            return "#{year}-#{month}-#{day}"
          end

          # Try ISO format
          parse_chinese_date(text) # Reuse the base class method for ISO dates
        end

        # Fetch and parse an individual announcement
        # @param url [String]
        # @return [Hash, nil]
        def fetch_and_parse_announcement(url)
          puts "[MidPage] Fetching announcement: #{url}" if verbose?

          begin
            detail_page = @agent.get(url)
          rescue StandardError => e
            puts "[MidPage] Error fetching #{url}: #{e.message}" if verbose?
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
          content = page.search('.news-content, article, .content, #content').first
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
          # Look for number patterns
          match = text.match(%r{№\s*(\d+[/-]?\d*)})
          return "№#{match[1]}" if match

          nil
        end

        # Extract announcement date
        # @param text [String]
        # @return [String, nil]
        def extract_announcement_date(text)
          parse_russian_date(text)
        end

        # Extract title from page
        # @param page [Mechanize::Page]
        # @return [String, nil]
        def extract_title(page)
          title_node = page.search('h1, .title, #title, .news-title').first
          extract_text(title_node)
        end

        # Extract sanctioned entities
        # @param text [String]
        # @return [Array<Hash>]
        def extract_entities_from_text(text)
          entities = []

          # MID announcements often have bilingual names (Russian and English)
          # Pattern: "Иванов Иван Иванович (Ivanov Ivan Ivanovich) – должность"
          # Or numbered lists

          current_entity_type = 'person' # MID stop-list is mostly persons

          text.each_line do |line|
            # Detect section headers
            if line.include?('Физические') || line.include?('граждане') || line.include?('перечень лиц')
              current_entity_type = 'person'
            elsif line.include?('Юридические') || line.include?('организации') || line.include?('компании')
              current_entity_type = 'organization'
            end

            # Extract entities
            # Pattern 1: Bilingual with title
            # "1. Рави Абделяль (Rawi Abdelal) – директор Центра..."
            match = line.match(/^\s*(\d+)\.\s*(.+?)\s*\((.+?)\)\s*[—–-]\s*(.+?)(?:\.|;|$)/i)
            if match
              entities << {
                index: match[1].to_i,
                russian_name: clean_russian_text(match[2]),
                english_name: match[3]&.strip,
                title: clean_russian_text(match[4]),
                entity_type: current_entity_type
              }
              next
            end

            # Pattern 2: Bilingual without title
            # "1. Иванов Иван (Ivanov Ivan)"
            match = line.match(/^\s*(\d+)\.\s*(.+?)\s*\((.+?)\)/)
            if match
              entities << {
                index: match[1].to_i,
                russian_name: clean_russian_text(match[2]),
                english_name: match[3]&.strip,
                title: nil,
                entity_type: current_entity_type
              }
              next
            end

            # Pattern 3: Russian name only with title
            # "1. Иванов Иван Иванович, директор..."
            match = line.match(/^\s*(\d+)\.\s*(.+?),\s*(.+?)(?:\.|;|$)/)
            next unless match

            name = clean_russian_text(match[2])
            # Check if it looks like a Russian name
            next unless name.match?(/\p{Cyrillic}/) && name.split.length >= 2

            entities << {
              index: match[1].to_i,
              russian_name: name,
              english_name: nil,
              title: clean_russian_text(match[3]),
              entity_type: current_entity_type
            }
          end

          entities
        end

        # Clean Russian text
        # @param text [String, nil]
        # @return [String, nil]
        def clean_russian_text(text)
          return nil if text.nil? || text.strip.empty?

          text.strip.gsub(/\s+/, ' ')
        end

        # Extract measures from text
        # @param text [String]
        # @return [Array<String>]
        def extract_measures_from_text(text)
          measures = []

          measure_patterns = [
            /запрет[^.]+въезд/i,
            /запрет[^.]+въезда/i,
            /запрещени[^.]+въезд/i,
            /замораживан[^.]+актив/i,
            /ограничен[^.]+финансов/i
          ]

          measure_patterns.each do |pattern|
            text.scan(pattern).each do |match|
              measures << clean_russian_text(match)
            end
          end

          measures.uniq
        end

        # Extract reason from text
        # @param text [String]
        # @return [String, nil]
        def extract_reason_from_text(text)
          # Look for reason patterns
          match = text.match(/В\s+связи\s+с[^.]+\./i)
          return clean_russian_text(match[0]) if match

          match = text.match(/в\s+ответ[^.]+\./i)
          return clean_russian_text(match[0]) if match

          nil
        end
      end
    end
  end
end
