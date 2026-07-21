# frozen_string_literal: true

# Load Lutaml::Model first
require 'lutaml/model'

# Switzerland Source Models for Ammitto
#
# This module contains Lutaml::Model classes that map to the Swiss SECO
# sanctions list XML format. These models preserve the exact structure
# of the source data for YAML serialization.
#
# @example Loading CH data
#   require 'ammitto/sources/ch'
#
#   xml = File.read('seco_sanctions.xml')
#   list = Ammitto::Sources::Ch::SanctionsList.from_xml(xml)
#
#   list.individuals.each do |individual|
#     puts individual.id
#     puts individual.full_name
#   end
#
# @example Saving to YAML
#   yaml = list.to_yaml
#   File.write("ch_sanctions.yaml", yaml)
#
# @example Loading from YAML
#   list = Ammitto::Sources::Ch::SanctionsList.from_yaml(yaml)
#

module Ammitto
  module Sources
    module Ch
      # Source code for Switzerland
      SOURCE_CODE = :ch

      # Human-readable source name
      SOURCE_NAME = 'Switzerland (SECO)'

      # Source API endpoint
      SOURCE_URL = 'https://www.seco.admin.ch/seco/de/home/Aussenwirtschaftspolitik_Wirtschaftliche_Zusammenarbeit/Wirtschaftsbeziehungen/exportkontrollen-und-sanktionen/sanktionsmassnahmen/sanktionsliste.html'

      # Country code (ISO 3166-1 alpha-2)
      COUNTRY_CODE = 'CH'
    end
  end
end

# Load all CH source models
require_relative 'ch/sanctions_list'
require_relative 'ch/transformer'
