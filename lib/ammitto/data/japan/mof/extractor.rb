# frozen_string_literal: true

require 'mechanize'
require 'fileutils'
require 'date'

module Ammitto
  module Data
    module Japan
      module Mof
        # Web scraper for Japan MOF Asset Freeze List
        #
        # Downloads the Excel file containing sanctioned entities from the
        # Japan Ministry of Finance website.
        #
        # @example Download the Excel file
        #   extractor = Extractor.new
        #   xlsx_path = extractor.download('/tmp/mof')
        #   # => "/tmp/mof/asset_freeze_20260306.xlsx"
        #
        # @example Download and parse in one step
        #   extractor = Extractor.new
        #   lists = extractor.fetch('/tmp/mof')
        #   # => [List, List, ...]
        #
        class Extractor
          # Base URL for MOF website
          BASE_URL = 'https://www.mof.go.jp'

          # Index page for economic sanctions
          INDEX_URL = "#{BASE_URL}/policy/international_policy/gaitame_kawase/gaitame/economic_sanctions/list.html".freeze

          # User agent for web requests
          USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15'

          attr_reader :agent, :source_url, :source_file, :options

          # Initialize extractor
          # @param options [Hash] Extraction options
          # @option options [Boolean] :verbose Enable verbose output
          # @option options [Integer] :timeout Request timeout in seconds
          def initialize(options = {})
            @options = options
            @agent = Mechanize.new do |a|
              a.user_agent = USER_AGENT
              a.follow_meta_refresh = true
              a.redirect_ok = true
              a.open_timeout = options[:timeout] || 60
              a.read_timeout = options[:timeout] || 120
            end
            @source_url = nil
            @source_file = nil
          end

          # Download the Excel file from MOF website
          # @param output_dir [String] Directory to save the file
          # @return [String, nil] Path to downloaded file or nil on failure
          def download(output_dir = '.')
            log "Fetching #{INDEX_URL}..."

            page = agent.get(INDEX_URL)

            # Find the Excel file link containing '資産凍結等対象者一覧'
            excel_link = find_excel_link(page)

            unless excel_link
              log 'ERROR: Could not find Excel file link'
              return nil
            end

            log "Found link: #{excel_link.text.strip}"
            log "URL: #{excel_link.href}"

            # Download the file
            file_page = agent.click(excel_link)
            @source_url = file_page.uri.to_s

            FileUtils.mkdir_p(output_dir)

            filename = extract_filename(file_page)
            output_path = File.join(output_dir, filename)
            file_page.save_as(output_path)

            @source_file = output_path
            log "Downloaded to: #{output_path}"
            output_path
          rescue Mechanize::ResponseCodeError => e
            log "Failed to fetch page: #{e.message}"
            nil
          rescue StandardError => e
            log "Error downloading file: #{e.message}"
            nil
          end

          # Download and parse in one step
          # @param output_dir [String] Directory for output files
          # @return [Array<List>] Parsed sanction lists
          def fetch(output_dir)
            xlsx_path = download(output_dir)
            return [] unless xlsx_path

            require_relative 'list'
            List.from_xlsx(xlsx_path, source_url: source_url)
          end

          # Download, parse, and generate YAML files
          # @param output_dir [String] Directory for YAML output
          # @return [Array<String>] Paths to generated YAML files
          def fetch_to_yaml(output_dir)
            xlsx_path = download(File.join(output_dir, 'raw'))
            return [] unless xlsx_path

            require_relative 'list'
            lists = List.from_xlsx(xlsx_path, source_url: source_url)

            yaml_paths = []
            date_str = Date.today.strftime('%Y%m%d')

            lists.each do |list|
              yaml_path = list.to_yaml_file(output_dir, date_str)
              yaml_paths << yaml_path
              log "Generated: #{yaml_path}"
            end

            yaml_paths
          end

          # Get last modified date from MOF website
          # @return [Date, nil] Last modified date or nil if unavailable
          def last_modified
            return @last_modified if defined?(@last_modified)

            page = agent.get(INDEX_URL)

            # Look for date patterns in the page
            text = page.body

            # Japanese date format: 2026年3月5日
            match = text.match(/(\d{4})年(\d{1,2})月(\d{1,2})日/)
            if match
              year = match[1].to_i
              month = match[2].to_i
              day = match[3].to_i
              @last_modified = Date.new(year, month, day)
            else
              @last_modified = nil
            end
          rescue StandardError
            @last_modified = nil
          end

          private

          # Find the Excel download link on the page
          # @param page [Mechanize::Page] The page to search
          # @return [Mechanize::Page::Link, nil] The Excel link or nil
          def find_excel_link(page)
            # First try to find link with specific text
            excel_link = page.links.find do |l|
              l.text.include?('資産凍結等対象者一覧') &&
                (l.text.include?('Excel') || l.href&.match?(/\.(xlsx?|xls)$/i))
            end

            # Fallback: find any Excel file link
            excel_link ||= page.links.find { |l| l.href&.match?(/\.(xlsx?|xls)$/i) }

            excel_link
          end

          # Extract filename from response headers or URL
          # @param page [Mechanize::Page] The downloaded file page
          # @return [String] The filename
          def extract_filename(page)
            # Try Content-Disposition header
            if page.response['content-disposition']
              match = page.response['content-disposition'].match(/filename="?([^";]+)"?/)
              return match[1] if match
            end

            # Fallback to URL path
            File.basename(page.uri.path)
          end

          # Log message if verbose mode enabled
          # @param message [String] Message to log
          def log(message)
            puts message if options[:verbose]
          end

          class << self
            # Download the Excel file
            # @param output_dir [String] Directory to save the file
            # @param options [Hash] Extraction options
            # @return [String, nil] Path to downloaded file
            def download(output_dir, options = {})
              new(options).download(output_dir)
            end

            # Download and parse in one step
            # @param output_dir [String] Directory for output
            # @param options [Hash] Extraction options
            # @return [Array<List>] Parsed sanction lists
            def fetch(output_dir, options = {})
              new(options).fetch(output_dir)
            end

            # Download, parse, and generate YAML files
            # @param output_dir [String] Directory for YAML output
            # @param options [Hash] Extraction options
            # @return [Array<String>] Paths to generated YAML files
            def fetch_to_yaml(output_dir, options = {})
              new(options).fetch_to_yaml(output_dir)
            end
          end
        end
      end
    end
  end
end
