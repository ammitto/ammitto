# frozen_string_literal: true

# RU source models (Lutaml::Model)
require_relative 'ru/sanctions_list'
require_relative 'ru/transformer'

module Ammitto
  # RuSource handles Russia (MID) sanctions data
  #
  # Russia publishes sanctions as:
  # - Стоп-лист (Stop-list) by Ministry of Foreign Affairs (MID)
  # - Central Bank financial sanctions
  # - Government decrees
  #
  # Data is published as HTML announcements.
  #
  # @example
  #   source = RuSource.new
  #   data = source.load_data
  #   results = source.search("Biden", data)
  #
  class RuSource < BaseSource
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

  # Register the source
  Registry.register(:ru, RuSource)
end
