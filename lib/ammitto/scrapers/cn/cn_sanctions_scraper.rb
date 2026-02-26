# frozen_string_literal: true

require_relative 'mofcom_page'
require_relative 'mfa_page'

module Ammitto
  module Scrapers
    module Cn
      # CnSanctionsScraper fetches all China sanctions data from multiple sources
      #
      # Combines data from:
      # - MOFCOM (Unreliable Entity List, Export Control List)
      # - MFA (Anti-Sanctions List)
      #
      # @example Fetching all China sanctions
      #   scraper = Ammitto::Scrapers::Cn::CnSanctionsScraper.new(verbose: true)
      #   all_data = scraper.fetch_all
      #
      class CnSanctionsScraper
        # @return [Hash] scraper options
        attr_reader :options

        # Initialize with options
        # @param options [Hash] scraper options
        # @option options [Boolean] :verbose (false) Enable verbose logging
        # @option options [Boolean] :mofcom (true) Include MOFCOM data
        # @option options [Boolean] :mfa (true) Include MFA data
        def initialize(options = {})
          @options = options
        end

        # Fetch all China sanctions data
        # @return [Hash] { announcements: [...], entities: [...], errors: [...] }
        def fetch_all
          announcements = []
          entities = []
          errors = []

          # Fetch MOFCOM data
          if options[:mofcom] != false
            mofcom_result = fetch_mofcom_data
            announcements.concat(mofcom_result[:announcements])
            entities.concat(mofcom_result[:entities])
            errors.concat(mofcom_result[:errors])
          end

          # Fetch MFA data
          if options[:mfa] != false
            mfa_result = fetch_mfa_data
            announcements.concat(mfa_result[:announcements])
            entities.concat(mfa_result[:entities])
            errors.concat(mfa_result[:errors])
          end

          {
            announcements: announcements,
            entities: entities,
            errors: errors
          }
        end

        # Fetch only MOFCOM data
        # @return [Hash]
        def fetch_mofcom_data
          puts '[CnSanctionsScraper] Fetching MOFCOM data...' if verbose?

          announcements = []
          entities = []
          errors = []

          # Fetch Unreliable Entity List
          [:unreliable_entity, :export_control].each do |list_type|
            begin
              scraper = MofcomPage.new(list_type: list_type, options: options)
              result = scraper.fetch_all_announcements

              result.each do |announcement|
                announcements << announcement

                # Extract entities from announcement
                (announcement[:entities] || []).each do |entity_data|
                  entities << build_entity(entity_data, announcement)
                end
              end
            rescue StandardError => e
              errors << { source: "mofcom_#{list_type}", error: e.message }
              puts "[CnSanctionsScraper] MOFCOM #{list_type} error: #{e.message}" if verbose?
            end
          end

          { announcements: announcements, entities: entities, errors: errors }
        end

        # Fetch only MFA data
        # @return [Hash]
        def fetch_mfa_data
          puts '[CnSanctionsScraper] Fetching MFA data...' if verbose?

          announcements = []
          entities = []
          errors = []

          begin
            scraper = MfaPage.new(options)
            result = scraper.fetch_all_announcements

            result.each do |announcement|
              announcements << announcement

              # Extract entities from announcement
              (announcement[:entities] || []).each do |entity_data|
                entities << build_entity(entity_data, announcement)
              end
            end
          rescue StandardError => e
            errors << { source: 'mfa', error: e.message }
            puts "[CnSanctionsScraper] MFA error: #{e.message}" if verbose?
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
            chinese_name: entity_data[:chinese_name],
            english_name: entity_data[:english_name],
            entity_type: entity_data[:entity_type] || 'organization',
            list_type: announcement[:list_type],
            announcement_number: announcement[:announcement_number],
            announcement_date: announcement[:date],
            effective_date: announcement[:date],
            reason: announcement[:reason],
            measures: announcement[:measures] || [],
            legal_basis: announcement[:legal_basis] || [],
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
