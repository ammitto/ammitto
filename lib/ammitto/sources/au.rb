# frozen_string_literal: true

# Load Lutaml::Model first
require 'lutaml/model'

# Australia Source Models for Ammitto
#
# This module contains Lutaml::Model classes that map to the Australian DFAT
# sanctions list CSV/XLSX format. These models preserve the exact structure
# of the source data for YAML serialization.
#
# @example Loading AU data
#   require 'ammitto/sources/au'
#
#   csv = File.read('Australian_Sanctions_Consolidated_List.csv')
#   list = Ammitto::Sources::Au::SanctionsList.from_csv(csv)
#
#   list.individuals.each do |individual|
#     puts individual.id
#     puts individual.full_name
#   end
#
# @example Saving to YAML
#   yaml = list.to_yaml
#   File.write("au_sanctions.yaml", yaml)
#
# @example Loading from YAML
#   list = Ammitto::Sources::Au::SanctionsList.from_yaml(yaml)
#

module Ammitto
  module Sources
    module Au
      # Source code for Australia
      SOURCE_CODE = :au

      # Human-readable source name
      SOURCE_NAME = 'Australia (DFAT)'

      # Source API endpoint (XLSX converted to CSV)
      SOURCE_URL = 'https://www.dfat.gov.au/sites/default/files/Australian_Sanctions_Consolidated_List.xlsx'

      # Country code (ISO 3166-1 alpha-2)
      COUNTRY_CODE = 'AU'
    end
  end
end

# Load all AU source models
require_relative 'au/sanctions_list'
require_relative 'au/transformer'
