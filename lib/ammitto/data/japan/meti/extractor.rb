# frozen_string_literal: true

require 'mechanize'
require 'fileutils'
require 'tempfile'
require_relative 'foreign_user_list'

module Ammitto
  module Data
    module Japan
      module METI
        # Extractor downloads the METI Foreign User List Excel file
        #
        # The list is published as an Excel file on the METI website.
        # This extractor uses Mechanize to navigate and download the file.
        #
        # @example Basic usage
        #   extractor = Ammitto::Data::Japan::METI::Extractor.new
        #   xlsx_path = extractor.download
        #   list = extractor.fetch
        #
        # @example With output directory
        #   extractor = Ammitto::Data::Japan::METI::Extractor.new(output_dir: './downloads')
        #   xlsx_path = extractor.download
        #
        class Extractor
          # @return [String] METI law page URL
          INDEX_URL = 'https://www.meti.go.jp/policy/anpo/law00.html'

          # @return [String, nil] Last downloaded file path
          attr_reader :last_download_path

          # @return [String, nil] Last download URL
          attr_reader :last_download_url

          # @return [Mechanize] Mechanize agent
          attr_reader :agent

          # @return [Boolean] verbose output mode
          attr_accessor :verbose

          # @return [String] output directory for downloads
          attr_reader :output_dir

          # Initialize the extractor
          #
          # @param output_dir [String] directory to save downloaded files
          # @param verbose [Boolean] enable verbose output
          #
          def initialize(output_dir: nil, verbose: false)
            @agent = Mechanize.new do |a|
              a.user_agent_alias = 'Mac Safari'
              a.follow_meta_refresh = true
              a.redirect_ok = true
              a.open_timeout = 60
              a.read_timeout = 120
            end
            @output_dir = output_dir || Dir.tmpdir
            @verbose = verbose
            @last_download_path = nil
            @last_download_url = nil
          end

          # Download the Foreign User List Excel file
          #
          # @param save_to [String, nil] specific path to save file
          # @return [String] path to the downloaded file
          # @raise [RuntimeError] if download fails
          #
          def download(save_to: nil)
            puts "[jp_meti] Fetching #{INDEX_URL}..." if verbose?

            page = agent.get(INDEX_URL)

            # Find the Foreign User List link (外国ユーザーリスト)
            # Exclude "について" (about) pages
            ful_link = page.links.find do |l|
              text = l.text.strip
              text == '外国ユーザーリスト' ||
                (text.include?('外国ユーザーリスト') && !text.include?('について') && !text.include?('Q&A'))
            end

            ful_link ||= page.links.find { |l| l.href&.match?(/\.xlsx?$/i) && l.text.include?('外国ユーザー') }

            raise 'Could not find Foreign User List link on METI website' unless ful_link

            puts "[jp_meti] Found link: #{ful_link.text.strip} => #{ful_link.href}" if verbose?

            # Download the file
            file_page = agent.click(ful_link)

            # Capture the download URL
            @last_download_url = file_page.uri.to_s

            # Determine save path
            filename = extract_filename(file_page)
            save_path = save_to || File.join(output_dir, filename)

            # Ensure output directory exists
            FileUtils.mkdir_p(File.dirname(save_path))

            # Save the file
            file_page.save_as(save_path)

            @last_download_path = save_path

            puts "[jp_meti] Downloaded to: #{save_path}" if verbose?

            save_path
          end

          # Fetch and parse the Foreign User List
          #
          # @return [ForeignUserList] the parsed list
          #
          def fetch
            xlsx_path = download
            ForeignUserList.from_xlsx(xlsx_path, source_url: last_download_url)
          end

          # Get the source code for this extractor
          # @return [Symbol]
          def code
            :jp_meti
          end

          # Get the authority name
          # @return [String]
          def authority_name
            'Japan METI (Ministry of Economy, Trade and Industry)'
          end

          # Get the API endpoint
          # @return [String]
          def api_endpoint
            INDEX_URL
          end

          # Get authority information
          # @return [Hash]
          def authority
            {
              id: 'jp_meti',
              name: authority_name,
              country_code: 'JP'
            }
          end

          private

          # Extract filename from response
          # @param page [Mechanize::Page, Mechanize::File] the downloaded page
          # @return [String] the filename
          def extract_filename(page)
            # Try Content-Disposition header
            if page.response['content-disposition']
              match = page.response['content-disposition'].match(/filename="?([^";]+)"?/)
              return match[1] if match
            end

            # Fall back to URI path
            File.basename(page.uri.path)
          end

          # Check if verbose mode is enabled
          # @return [Boolean]
          def verbose?
            @verbose || ENV['AMMITTO_VERBOSE'] == 'true'
          end
        end
      end
    end
  end
end
