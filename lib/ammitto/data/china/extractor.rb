# frozen_string_literal: true

require 'mechanize'
require 'nokogiri'
require 'json'

module Ammitto
  module Data
    module China
      # Base extractor for Chinese government sanctions data
      #
      # Provides common functionality for fetching data from Chinese government
      # websites (MOFCOM, MFA, etc.)
      #
      class Extractor
        # Base URL for MOFCOM announcements
        MOFCOM_BASE_URL = 'https://www.mofcom.gov.cn'

        # Base URL for MFA announcements
        MFA_BASE_URL = 'https://www.mfa.gov.cn'

        # User agent for web requests
        USER_AGENT = 'Mozilla/5.0 (compatible; AmmittoDataBot/1.0; +https://www.ammitto.org)'

        # Available source types
        SOURCES = %w[
          mofcom-unreliable-entity-list
          mofcom-export-control-list
          mfa-anti-sanction-list
        ].freeze

        attr_reader :source, :agent, :options

        # Initialize extractor
        # @param source [Symbol, String] Source identifier
        # @param options [Hash] Extraction options
        def initialize(source, options = {})
          @source = source.to_s
          @options = options
          @agent = Mechanize.new do |a|
            a.user_agent = USER_AGENT
            a.open_timeout = 30
            a.read_timeout = 60
            a.max_history = 10
          end
        end

        # Fetch data from the source
        # @return [Array<Hash>] Extracted data
        def fetch
          case source
          when 'mofcom-unreliable-entity-list'
            fetch_mofcom_unreliable_entity_list
          when 'mofcom-export-control-list'
            fetch_mofcom_export_control_list
          when 'mfa-anti-sanction-list'
            fetch_mfa_anti_sanction_list
          else
            raise ArgumentError, "Unknown source: #{source}"
          end
        end

        # Fetch data and save to YAML files in output directory
        # @param output_dir [String] Output directory path
        # @return [Integer] Number of items extracted
        def fetch_to_yaml(output_dir)
          data = fetch

          if data.empty?
            warn "No data extracted from #{source}" if options[:verbose]
            return 0
          end

          # Save to YAML files
          require 'fileutils'
          FileUtils.mkdir_p(output_dir)

          data.each_with_index do |item, index|
            filename = generate_filename(item, index)
            filepath = File.join(output_dir, filename)
            File.write(filepath, item.to_yaml)
          end

          data.size
        end

        # Get list of available sources
        # @return [Array<String>]
        def self.available_sources
          SOURCES
        end

        # Check if source is valid
        # @param source [String] Source name
        # @return [Boolean]
        def self.valid_source?(source)
          SOURCES.include?(source.to_s)
        end

        private

        # Generate filename for extracted item
        # @param item [Hash] Extracted item
        # @param _index [Integer] Item index
        # @return [String] Filename
        def generate_filename(item, _index)
          date = item[:publish_date] || Date.today.to_s
          date_slug = date.gsub('-', '')

          # Generate ID from title
          id = item[:title].to_s
                           .gsub(/[^\u4e00-\u9fa5a-zA-Z0-9\s-]/, '')
                           .gsub(/\s+/, '-')
                           .gsub(/-+/, '-')
                           .downcase
                           .slice(0, 50)

          "#{date_slug}-#{id}.yml"
        end

        # Fetch MOFCOM Unreliable Entity List announcements
        # @return [Array<Hash>]
        def fetch_mofcom_unreliable_entity_list
          results = []

          # MOFCOM unreliable entity list announcements are in the 公告 section
          url = "#{MOFCOM_BASE_URL}/zwgk/zcfb/art/"

          begin
            page = agent.get(url)

            # Find announcement links for unreliable entity list
            page.links.each do |link|
              next unless unreliable_entity_list_link?(link)

              announcement_data = extract_mofcom_announcement(link)
              results << announcement_data if announcement_data
            end
          rescue Mechanize::ResponseCodeError => e
            warn "Failed to fetch MOFCOM UEL: #{e.message}" if options[:verbose]
          end

          results
        end

        # Fetch MOFCOM Export Control List announcements
        # @return [Array<Hash>]
        def fetch_mofcom_export_control_list
          results = []

          # Similar pattern to UEL but different section
          url = "#{MOFCOM_BASE_URL}/zwgk/zcfb/art/"

          begin
            page = agent.get(url)

            page.links.each do |link|
              next unless export_control_list_link?(link)

              announcement_data = extract_mofcom_announcement(link)
              results << announcement_data if announcement_data
            end
          rescue Mechanize::ResponseCodeError => e
            warn "Failed to fetch MOFCOM ECL: #{e.message}" if options[:verbose]
          end

          results
        end

        # Fetch MFA Anti-Sanctions List announcements
        # @return [Array<Hash>]
        def fetch_mfa_anti_sanction_list
          results = []

          # MFA announcements are in different section
          url = "#{MFA_BASE_URL}/web/zwyw_674879/"

          begin
            page = agent.get(url)

            page.links.each do |link|
              next unless anti_sanction_list_link?(link)

              announcement_data = extract_mfa_announcement(link)
              results << announcement_data if announcement_data
            end
          rescue Mechanize::ResponseCodeError => e
            warn "Failed to fetch MFA ASL: #{e.message}" if options[:verbose]
          end

          results
        end

        # Check if link is for unreliable entity list
        # @param link [Mechanize::Page::Link] Link object
        # @return [Boolean]
        def unreliable_entity_list_link?(link)
          text = link.text.to_s
          text.include?('不可靠实体清单') || text.include?('Unreliable Entity List')
        end

        # Check if link is for export control list
        # @param link [Mechanize::Page::Link] Link object
        # @return [Boolean]
        def export_control_list_link?(link)
          text = link.text.to_s
          text.include?('出口管制管控名单') || text.include?('Export Control')
        end

        # Check if link is for anti-sanctions list
        # @param link [Mechanize::Page::Link] Link object
        # @return [Boolean]
        def anti_sanction_list_link?(link)
          text = link.text.to_s
          text.include?('反制裁') || text.include?('Anti-Sanction')
        end

        # Extract announcement data from MOFCOM page
        # @param link [Mechanize::Page::Link] Link to announcement
        # @return [Hash, nil]
        def extract_mofcom_announcement(link)
          page = link.click

          {
            url: page.uri.to_s,
            title: extract_title(page),
            content: extract_content(page),
            publish_date: extract_publish_date(page),
            authority: '中华人民共和国商务部',
            source: 'mofcom'
          }
        rescue StandardError => e
          warn "Error extracting announcement: #{e.message}" if options[:verbose]
          nil
        end

        # Extract announcement data from MFA page
        # @param link [Mechanize::Page::Link] Link to announcement
        # @return [Hash, nil]
        def extract_mfa_announcement(link)
          page = link.click

          {
            url: page.uri.to_s,
            title: extract_title(page),
            content: extract_content(page),
            publish_date: extract_publish_date(page),
            authority: '中华人民共和国外交部',
            source: 'mfa'
          }
        rescue StandardError => e
          warn "Error extracting announcement: #{e.message}" if options[:verbose]
          nil
        end

        # Extract title from page
        # @param page [Mechanize::Page] Page object
        # @return [String]
        def extract_title(page)
          # Try common title selectors for Chinese government sites
          page.at('h1')&.text&.strip ||
            page.at('.title')&.text&.strip ||
            page.at('title')&.text&.strip.to_s.split(/[-_|]/).first&.strip
        end

        # Extract content from page
        # @param page [Mechanize::Page] Page object
        # @return [String]
        def extract_content(page)
          # Try common content selectors for Chinese government sites
          content_node = page.at('.content') ||
                         page.at('.article-content') ||
                         page.at('.TRS_Editor') ||
                         page.at('article') ||
                         page.at('.content-con')

          content_node&.text&.strip || ''
        end

        # Extract publish date from page
        # @param page [Mechanize::Page] Page object
        # @return [String, nil]
        def extract_publish_date(page)
          # Look for date patterns in content
          text = page.body

          # Common date patterns in Chinese government sites
          patterns = [
            /(\d{4})年(\d{1,2})月(\d{1,2})日/, # 2024年01月15日
            /(\d{4})-(\d{2})-(\d{2})/, # 2024-01-15
            /发布时间[：:]\s*(\d{4})-(\d{2})-(\d{2})/ # 发布时间：2024-01-15
          ]

          patterns.each do |pattern|
            match = text.match(pattern)
            if match
              year, month, day = match[1..3].map { |s| s.to_s.rjust(2, '0') }
              return "#{year}-#{month}-#{day}"
            end
          end

          nil
        end

        class << self
          # Create extractor for source
          # @param source [Symbol, String] Source identifier
          # @param options [Hash] Options
          # @return [Extractor]
          def for_source(source, options = {})
            new(source, options)
          end

          # Run extraction and save to output directory
          # @param source [Symbol, String] Source identifier
          # @param output_dir [String] Output directory path
          # @param options [Hash] Options
          # @return [Integer] Number of items extracted
          def run(source, output_dir, options = {})
            extractor = new(source, options)
            data = extractor.fetch

            if data.empty?
              warn "No data extracted from #{source}"
              return 0
            end

            # Save to YAML files
            require 'fileutils'
            FileUtils.mkdir_p(output_dir)

            data.each_with_index do |item, index|
              filename = generate_filename(item, index)
              filepath = File.join(output_dir, filename)
              File.write(filepath, item.to_yaml)
            end

            data.size
          end

          private

          def generate_filename(item, _index)
            date = item[:publish_date] || Date.today.to_s
            date_slug = date.gsub('-', '')

            # Generate ID from title
            id = item[:title].to_s
                             .gsub(/[^\u4e00-\u9fa5a-zA-Z0-9\s-]/, '')
                             .gsub(/\s+/, '-')
                             .gsub(/-+/, '-')
                             .downcase
                             .slice(0, 50)

            "#{date_slug}-#{id}.yml"
          end
        end
      end
    end
  end
end
