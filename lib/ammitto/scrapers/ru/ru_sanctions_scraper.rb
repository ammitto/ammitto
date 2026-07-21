# frozen_string_literal: true

require_relative 'mid_page'

module Ammitto
  module Scrapers
    module Ru
      # RuSanctionsScraper fetches all Russia sanctions data from multiple sources
      #
      # Combines data from:
      # - MID (Stop-list)
      #
      # @example Fetching all Russia sanctions
      #   scraper = Ammitto::Scrapers::Ru::RuSanctionsScraper.new(verbose: true)
      #   all_data = scraper.fetch_all
      #
      class RuSanctionsScraper
        # @return [Hash] scraper options
        attr_reader :options

        # Initialize with options
        # @param options [Hash] scraper options
        # @option options [Boolean] :verbose (false) Enable verbose logging
        # @option options [Boolean] :mid (true) Include MID data
        def initialize(options = {})
          @options = options
        end

        # Fetch all Russia sanctions data
        # @return [Hash] { announcements: [...], entities: [...], errors: [...] }
        def fetch_all
          announcements = []
          entities = []
          errors = []

          # Fetch MID data
          if options[:mid] != false
            mid_result = fetch_mid_data
            announcements.concat(mid_result[:announcements])
            entities.concat(mid_result[:entities])
            errors.concat(mid_result[:errors])
          end

          {
            announcements: announcements,
            entities: entities,
            errors: errors
          }
        end

        # Fetch only MID data
        # @return [Hash]
        def fetch_mid_data
          puts '[RuSanctionsScraper] Fetching MID data...' if verbose?

          announcements = []
          entities = []
          errors = []

          begin
            scraper = MidPage.new(options)
            result = scraper.fetch_all_announcements

            result.each do |announcement|
              announcements << announcement

              # Extract entities from announcement
              (announcement[:entities] || []).each do |entity_data|
                entities << build_entity(entity_data, announcement)
              end
            end
          rescue StandardError => e
            errors << { source: 'mid', error: e.message }
            puts "[RuSanctionsScraper] MID error: #{e.message}" if verbose?
          end

          { announcements: announcements, entities: entities, errors: errors }
        end

        private

        # Build an entity hash from parsed data
        # @param entity_data [Hash] parsed entity data
        # @param announcement [Hash] parent announcement data
        # @return [Hash]
        def build_entity(entity_data, announcement)
          {
            russian_name: entity_data[:russian_name],
            english_name: entity_data[:english_name],
            entity_type: entity_data[:entity_type] || 'person',
            list_type: announcement[:list_type],
            announcement_number: announcement[:announcement_number],
            announcement_date: announcement[:date],
            effective_date: announcement[:date],
            reason: announcement[:reason],
            measures: announcement[:measures] || [],
            source_url: announcement[:source_url],
            title: entity_data[:title]
          }
        end

        # Check if verbose mode is enabled
        # @return [Boolean]
        def verbose?
          options[:verbose] || ENV['AMMITTO_VERBOSE'] == 'true'
        end
      end
    end
  end
end
