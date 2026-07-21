# frozen_string_literal: true

# RU source models (Lutaml::Model)
require_relative 'sanctions_list'
require_relative 'transformer'

module Ammitto
  module Sources
    module Ru
      # Source handles Russia (MID) sanctions data
      #
      # Russia publishes sanctions as:
      # - Стоп-лист (Stop-list) by Ministry of Foreign Affairs (MID)
      # - Central Bank financial sanctions
      # - Government decrees
      #
      # Data is published as HTML announcements.
      #
      # @example
      #   source = Ammitto::Sources::Ru::Source.new
      #   data = source.load_data
      #   results = source.search("Biden", data)
      #
      class Source < BaseSource
        # @return [Symbol] the source code
        def code
          :ru
        end

        # @return [Authority] the Russia authority
        def authority
          @authority ||= Authority.find('ru')
        end

        # Get the MID website
        # @return [String] the MID URL
        def mid_url
          'https://mid.ru'
        end

        # Get the Central Bank website
        # @return [String] the CBR URL
        def cbr_url
          'https://cbr.ru'
        end
      end
    end
  end
end

# Register the source
Ammitto::Registry.register(:ru, Ammitto::Sources::Ru::Source)
