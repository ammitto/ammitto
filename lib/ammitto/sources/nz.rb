# frozen_string_literal: true

# Load Lutaml::Model first
require 'lutaml/model'

# New Zealand Source Models for Ammitto
#
# This module contains Lutaml::Model classes that map to the New Zealand MFAT
# Russia Sanctions Register XLSX format.
#
# NZ maintains Russia-specific sanctions under the Russia Sanctions Act 2022.
# Note: NZ also implements UN sanctions, but those are covered by the UN source.
#
# The register contains:
# - Individuals (1850+ entries)
# - Entities/Organizations
# - Ships
#
# @example Loading NZ data
#   require 'ammitto/sources/nz'
#
#   list = Ammitto::Sources::Nz::SanctionsList.from_xlsx('russia-sanctions-register.xlsx')
#
#   list.individuals.each do |individual|
#     puts individual.full_name
#     puts individual.unique_identifier
#   end
#
# @example Saving to YAML
#   yaml = list.to_yaml
#   File.write("nz_sanctions.yaml", yaml)
#

module Ammitto
  module Sources
    module Nz
      # Source code for New Zealand
      SOURCE_CODE = :nz

      # Human-readable source name
      SOURCE_NAME = 'New Zealand (MFAT)'

      # Source URL for Russia Sanctions Register
      SOURCE_URL = 'https://www.mfat.govt.nz/assets/Countries-and-Regions/Europe/Ukraine/Russia-Sanctions-Register.xlsx'

      # Country code (ISO 3166-1 alpha-2)
      COUNTRY_CODE = 'NZ'
    end
  end
end

# Load all NZ source models
require_relative 'nz/individual'
require_relative 'nz/entity'
require_relative 'nz/ship'
require_relative 'nz/sanctions_list'
