# frozen_string_literal: true

# Load Lutaml::Model first
require 'lutaml/model'

# Turkey Source Models for Ammitto
#
# This module contains Lutaml::Model classes that map to the Turkish Ministry
# of Treasury and Finance sanctions list XLSX format.
#
# Turkey has 4 sanction lists under Law No.6415 and Law No.7262:
#
# | List | Law | Description |
# |------|-----|-------------|
# | A | Article 5, Law No.6415 | UNSC resolutions |
# | B | Article 6, Law No.6415 | - |
# | C | Article 7, Law No.6415 | - |
# | D | Law No.7262, Art 3.A/3.B | - |
#
# The extractor handles List D (XLSX format) by default.
#
# @example Loading TR data
#   require 'ammitto/sources/tr'
#
#   list = Ammitto::Sources::Tr::SanctionsList.from_xlsx('turkey_sanctions.xlsx')
#
#   list.entities.each do |entity|
#     puts entity.name
#     puts entity.entity_type
#   end
#
# @example Saving to YAML
#   yaml = list.to_yaml
#   File.write("tr_sanctions.yaml", yaml)
#
# @example Loading from YAML
#   list = Ammitto::Sources::Tr::SanctionsList.from_yaml(yaml)
#

module Ammitto
  module Sources
    module Tr
      # Source code for Turkey
      SOURCE_CODE = :tr

      # Human-readable source name
      SOURCE_NAME = 'Turkey (Ministry of Treasury and Finance)'

      # Index pages for each list
      INDEX_PAGES = {
        a: 'https://en.hmb.gov.tr/5madde_ing',  # Article 5 - UNSC resolutions
        b: 'https://en.hmb.gov.tr/6madde_ing',  # Article 6
        c: 'https://en.hmb.gov.tr/7madde_ing',  # Article 7
        d: 'https://en.hmb.gov.tr/3a3b' # Law 7262, Articles 3.A/3.B
      }.freeze

      # Country code (ISO 3166-1 alpha-2)
      COUNTRY_CODE = 'TR'
    end
  end
end

# Load all TR source models
require_relative 'tr/sanctions_list'
