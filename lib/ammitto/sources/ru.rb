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
# The unit is the announcement: one file per MID publication, with the
# parties it names inside it. data-ru stores them under
# `sources/announcements/`.
#
# These examples described `Announcement.from_parsed_data` and a flat
# `{ russian_name:, english_name: }` entity shape until 2026-08-28. Neither
# existed — the class was not defined at all, and the repository has always
# stored `name: { ru:, en: }`.
#
# @example Loading an announcement
#   require 'ammitto/sources/ru'
#
#   announcement = Ammitto::Sources::Ru::Announcement.from_yaml(
#     File.read('sources/announcements/20220413-1.yml')
#   )
#   announcement.entities.first.english_name  # => "Peter Rey Aguilar"
#
# @example Harmonizing everyone it names
#   transformer = Ammitto::Sources::Ru::Transformer.new
#   result = transformer.transform_announcement(announcement)
#   result[:entities].length
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
require_relative 'ru/measure'
require_relative 'ru/instrument'
require_relative 'ru/entity'
require_relative 'ru/sanction_details'
require_relative 'ru/announcement_block'
require_relative 'ru/announcement'
require_relative 'ru/sanctions_list'
require_relative 'ru/transformer'
