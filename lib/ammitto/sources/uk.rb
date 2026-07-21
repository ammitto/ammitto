# frozen_string_literal: true

# Load Lutaml::Model first
require 'lutaml/model'

# UK Source Models for Ammitto
#
# This module contains Lutaml::Model classes that map to the UK OFSI
# sanctions list XML schema. These models preserve the exact structure
# of the source data for YAML serialization.
#
# @example Loading UK data
#   require 'ammitto/sources/uk'
#
#   xml = File.read('UK-Sanctions-List.xml')
#   designations = Ammitto::Sources::Uk::Designations.from_xml(xml)
#
#   designations.designations.each do |designation|
#     puts designation.unique_id
#     puts designation.primary_name&.full_name
#   end
#
# @example Saving to YAML
#   yaml = designation.to_yaml
#   File.write("AFG0001.yaml", yaml)
#
# @example Loading from YAML
#   designation = Ammitto::Sources::Uk::Designation.from_yaml(yaml)
#

module Ammitto
  module Sources
    module Uk
      # Source code for UK
      SOURCE_CODE = :uk

      # Human-readable source name
      SOURCE_NAME = 'United Kingdom (OFSI)'

      # Source API endpoint
      SOURCE_URL = 'https://sanctionslist.fcdo.gov.uk/docs/UK-Sanctions-List.xml'

      # Country code (ISO 3166-1 alpha-2)
      COUNTRY_CODE = 'GB'
    end
  end
end

# Load all UK source models (order matters for dependencies)
require_relative 'uk/sanctions_indicators'
require_relative 'uk/individual_details'
require_relative 'uk/address'
require_relative 'uk/non_latin_name'
require_relative 'uk/name'
require_relative 'uk/designation'
require_relative 'uk/designations'
require_relative 'uk/transformer'
