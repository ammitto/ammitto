# frozen_string_literal: true

# Load Lutaml::Model first
require 'lutaml/model'

# Russia Source Models for Ammitto
#
# This module contains Lutaml::Model classes that map to Russian sanctions
# announcements published by MID (Ministry of Foreign Affairs) and CBR
# (Central Bank). Since Russia publishes data as HTML announcements
# (not structured XML/JSON), these models are populated after HTML parsing.
#
# Russia maintains:
# - Stop-list (Стоп-лист) - Entry bans on foreign persons
# - Central Bank sanctions
# - Government decrees (Постановления)
#
# @example Using RU models
#   require 'ammitto/sources/ru'
#
#   # After HTML parsing, create models
#   announcement = Ammitto::Sources::Ru::Announcement.from_parsed_data({
#     number: "2025-001",
#     date: "2025-01-15",
#     list_type: "stop_list",
#     entities: [{ russian_name: "...", english_name: "..." }]
#   })
#
# @example Saving to YAML
#   yaml = announcement.to_yaml
#   File.write("ru_announcement_2025_001.yaml", yaml)
#
# @example Loading from YAML
#   announcement = Ammitto::Sources::Ru::Announcement.from_yaml(yaml)
#

module Ammitto
  module Sources
    module Ru
      # Source code for Russia
      SOURCE_CODE = :ru

      # Human-readable source name
      SOURCE_NAME = 'Russia (MID/CBR)'

      # Source URLs
      SOURCE_URLS = {
        mid: 'https://mid.ru',
        cbr: 'https://cbr.ru'
      }.freeze

      # Country code (ISO 3166-1 alpha-2)
      COUNTRY_CODE = 'RU'
    end
  end
end

# Load all RU source models
require_relative 'ru/sanctions_list'
require_relative 'ru/transformer'
