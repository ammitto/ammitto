# frozen_string_literal: true

# Load Lutaml::Model first
require 'lutaml/model'

# Japan Source Models for Ammitto
#
# This module contains Lutaml::Model classes that map to the Japan End-User List
# published by the Ministry of Economy, Trade and Industry (METI).
#
# The End-User List is maintained under Japan's Foreign Exchange and Foreign
# Trade Act (FEFTA) and related export control regulations.
#
# Note: This list is primarily for export control purposes, not financial
# sanctions. It lists entities that may be involved in WMD proliferation.
#
# Data source is PDF-based and requires manual conversion to structured data.
#
# @example Loading Japan data
#   require 'ammitto/sources/jp'
#
#   entity = Ammitto::Sources::Jp::Entity.from_hash(data)
#   puts "#{entity.name} (#{entity.name_ja})"
#

module Ammitto
  module Sources
    module Jp
      # Source code for Japan
      SOURCE_CODE = :jp

      # Human-readable source name
      SOURCE_NAME = 'Japan End-User List (METI)'

      # Index page URL
      INDEX_URL = 'https://www.meti.go.jp/policy/anpo/english/law/doc/EndUserListE.html'

      # Country code
      COUNTRY_CODE = 'JP'

      # Legal basis
      LEGAL_BASIS = 'Foreign Exchange and Foreign Trade Act (FEFTA)'
    end
  end
end

# Load all Japan source models
require_relative 'jp/entity'
require_relative 'jp/sanctions_list'
