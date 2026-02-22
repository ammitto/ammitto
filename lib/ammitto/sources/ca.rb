# frozen_string_literal: true

# Load Lutaml::Model first
require 'lutaml/model'

# Canada Source Models for Ammitto
#
# This module contains Lutaml::Model classes that map to the Canadian SEFO
# sanctions list XML format. These models preserve the exact structure
# of the source data for YAML serialization.
#
# @example Loading CA data
#   require 'ammitto/sources/ca'
#
#   xml = File.read('consolidated_sem-x.xml')
#   list = Ammitto::Sources::Ca::SanctionsList.from_xml(xml)
#
#   list.individuals.each do |individual|
#     puts individual.id
#     puts individual.full_name
#   end
#
# @example Saving to YAML
#   yaml = list.to_yaml
#   File.write("ca_sanctions.yaml", yaml)
#
# @example Loading from YAML
#   list = Ammitto::Sources::Ca::SanctionsList.from_yaml(yaml)
#

module Ammitto
  module Sources
    module Ca
      # Source code for Canada
      SOURCE_CODE = :ca

      # Human-readable source name
      SOURCE_NAME = 'Canada (SEFO)'

      # Source API endpoint
      SOURCE_URL = 'https://www.international.gc.ca/world-monde/international_relations-relations_internationales/sanctions/consolidated-consolide.aspx?lang=eng'

      # Country code (ISO 3166-1 alpha-2)
      COUNTRY_CODE = 'CA'
    end
  end
end

# Load all CA source models
require_relative 'ca/sanctions_list'
require_relative 'ca/transformer'
