# frozen_string_literal: true

module Ammitto
  module Data
    module China
      # Ministry of Commerce (MOFCOM) data handling
      #
      # MOFCOM is responsible for:
      # - Unreliable Entity List (不可靠实体清单)
      # - Export Control List (出口管制管控名单)
      # - Import-Export Control List
      #
      module Mofcom
        # Base URL for MOFCOM announcements
        BASE_URL = 'https://www.mofcom.gov.cn'

        # Announcement categories
        CATEGORIES = {
          unreliable_entity_list: {
            path: '/zwgk/zcfb/',
            keywords: ['不可靠实体清单', 'Unreliable Entity List']
          },
          export_control_list: {
            path: '/zwgk/gldj/',
            keywords: ['出口管制管控名单', 'Export Control']
          }
        }.freeze

        # MOFCOM-specific extractor
        class Extractor < China::Extractor
          def initialize(list_type, options = {})
            @list_type = list_type.to_sym
            @category = CATEGORIES[list_type] || CATEGORIES[:unreliable_entity_list]
            super("mofcom-#{list_type}", options)
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
              source: 'mofcom',
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
            (page.at('.content') || page.at('.TRS_Editor') || page.at('article'))&.text&.strip
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
