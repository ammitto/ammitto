# frozen_string_literal: true

module Ammitto
  module Data
    module China
      # Ministry of Foreign Affairs (MFA) data handling
      #
      # MFA is responsible for:
      # - Anti-Sanctions List (反制裁清单)
      # - Countermeasures announcements
      #
      module Mfa
        # Base URL for MFA announcements
        BASE_URL = 'https://www.mfa.gov.cn'

        # MFA announcement categories
        CATEGORIES = {
          anti_sanction_list: {
            path: '/web/wjbz_673084/zwyw_673092/',
            keywords: %w[反制裁 Anti-Sanction 反制措施]
          }
        }.freeze

        # MFA-specific extractor
        class Extractor < China::Extractor
          def initialize(list_type = :anti_sanction_list, options = {})
            @list_type = list_type.to_sym
            @category = CATEGORIES[list_type] || CATEGORIES[:anti_sanction_list]
            super("mfa-#{list_type}", options)
          end

          # Fetch announcements for this list type
          # @return [Array<Hash>]
          def fetch
            url = "#{BASE_URL}#{@category[:path]}"
            page = agent.get(url)

            announcements = []
            page.links.each do |link|
              next unless matches_keywords?(link.text)

              data = extract_announcement(link)
              announcements << data if data
            end

            announcements
          end

          private

          def matches_keywords?(text)
            @category[:keywords].any? { |kw| text.include?(kw) }
          end

          def extract_announcement(link)
            page = link.click

            {
              url: page.uri.to_s,
              title: extract_title(page),
              content: extract_content(page),
              publish_date: extract_date(page),
              source: 'mfa',
              list_type: @list_type
            }
          rescue StandardError
            nil
          end

          def extract_title(page)
            page.at('h1')&.text&.strip ||
              page.at('.title')&.text&.strip ||
              page.title&.split(/[-_|]/)&.first&.strip
          end

          def extract_content(page)
            (page.at('.content') || page.at('.news-content') || page.at('article'))&.text&.strip
          end

          def extract_date(page)
            text = page.body
            match = text.match(/(\d{4})年(\d{1,2})月(\d{1,2})日/)
            return nil unless match

            year = match[1]
            month = match[2].rjust(2, '0')
            day = match[3].rjust(2, '0')
            "#{year}-#{month}-#{day}"
          end
        end

        class << self
          def available_lists
            CATEGORIES.keys
          end

          def fetch_all(options = {})
            results = {}
            available_lists.each do |list_type|
              extractor = Extractor.new(list_type, options)
              results[list_type] = extractor.fetch
            end
            results
          end
        end
      end
    end
  end
end
