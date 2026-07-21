# frozen_string_literal: true

# Load Lutaml::Model first
require 'lutaml/model'

# UN Vessels Source Models for Ammitto
#
# This module contains Lutaml::Model classes that map to the UN Security Council
# Designated Vessels List (1718 Committee - DPRK Sanctions).
#
# These vessels are designated under UN Security Council Resolution 1718 (2006)
# and subsequent resolutions related to DPRK sanctions.
#
# IMPORTANT: Vessels frequently change names and flags. IMO number is the
# key identifier.
#
# Data source is PDF-based and requires manual conversion to structured data.
#
# @example Loading UN Vessels data
#   require 'ammitto/sources/un_vessels'
#
#   vessel = Ammitto::Sources::UnVessels::Vessel.from_hash(data)
#   puts "#{vessel.vessel_name} (IMO: #{vessel.imo_number})"
#

module Ammitto
  module Sources
    module UnVessels
      # Source code for UN Vessels
      SOURCE_CODE = :un_vessels

      # Human-readable source name
      SOURCE_NAME = 'UN Security Council Designated Vessels (1718 Committee)'

      # Index page URL
      INDEX_URL = 'https://main.un.org/securitycouncil/sanctions/1718'

      # PDF URL
      PDF_URL = 'https://main.un.org/securitycouncil/sites/default/files/1718_designated_vessels_list_final.pdf'

      # Country code (International)
      COUNTRY_CODE = 'UN'

      # Legal basis
      LEGAL_BASIS = 'UN Security Council Resolution 1718 (2006) and subsequent resolutions'
    end
  end
end

# Load all UN Vessels source models
require_relative 'un_vessels/vessel'
require_relative 'un_vessels/sanctions_list'
