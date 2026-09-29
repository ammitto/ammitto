# frozen_string_literal: true

# Load Lutaml::Model first
require 'lutaml/model'

# EU Vessels Source Models for Ammitto
#
# This module contains Lutaml::Model classes that map to the EU Designated
# Vessels list hosted by the Danish Maritime Authority (DMA).
#
# The list carries vessels under Article 3s and Annex XLII of Council
# Regulation (EU) 833/2014 (Russia) and under Council Regulation (EU)
# 2017/1509 (DPRK); each row's "Subject to" cell says which (SubjectTo).
#
# IMPORTANT: Vessels can change names, so IMO number is the key identifier.
#
# @example Loading EU Vessels data
#   require 'ammitto/sources/eu_vessels'
#
#   list = Ammitto::Sources::EuVessels::SanctionsList.from_xlsx('vessels.xlsx')
#
#   list.vessels.each do |vessel|
#     puts "#{vessel.vessel_name} (IMO: #{vessel.imo_number})"
#   end
#

module Ammitto
  module Sources
    module EuVessels
      # Source code for EU Vessels
      SOURCE_CODE = :eu_vessels

      # Human-readable source name
      SOURCE_NAME = 'EU Designated Vessels (via Denmark DMA)'

      # Index page URL
      INDEX_URL = 'https://www.dma.dk/growth-and-framework-conditions/maritime-sanctions/general-information/eu-vessel-designations'

      # Country code (host country)
      COUNTRY_CODE = 'DK'
    end
  end
end

# Load all EU Vessels source models
require_relative 'eu_vessels/vessel'
require_relative 'eu_vessels/sanctions_list'
