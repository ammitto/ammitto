# frozen_string_literal: true

# Load Lutaml::Model first
require 'lutaml/model'

# Australia Source Models for Ammitto
#
# A fully normalized ontology for Australian sanctions data from the
# Department of Foreign Affairs and Trade (DFAT), as Lutaml::Model classes
# mapping the DFAT sanctions list CSV/XLSX format and preserving the
# structure of the source data for YAML serialization.
#
# This file is where the ontology as a whole is described; each model file
# carries only its own comment and points back here.
#
# Source: https://www.dfat.gov.au/sites/default/files/Australian_Sanctions_Consolidated_List.xlsx
#
# == Ontology overview
#
# The Australian sanctions ontology consists of these core concepts:
#
# 1. Entity - The sanctioned party (Individual, Organization, or Vessel)
# 2. Name - Name variants with script and type information
# 3. Sanction - The sanctions imposed (effects, regime, legal basis)
# 4. Legal Instrument - The law/regulation authorizing the sanction
# 5. Regime - The sanctions program (UN, autonomous, country-specific)
#
# == Data normalization
#
# The CSV data has a denormalized structure where one entity can span
# multiple rows (for different name variants). This ontology normalizes
# that data into proper objects:
#
#   CSV Row 1: 8577, Mohammad Salah JOKAR, Primary Name, ...
#   CSV Row 2: 8577a, محمد صالح جوکار, Original Script, ...
#   CSV Row 3: 8577b, Mohammad Saleh JOKAR, Alias, Strong, ...
#
# Becomes one Individual with three Name objects.
#
# == Entity types
#
# - Individual: A natural person with birth info, citizenship
# - Organization: A legal entity (company, group, institution)
# - Vessel: A ship with IMO number, flag state, tonnage
#
# == Sanction effects
#
# Australia imposes four types of sanctions measures:
#
# - Targeted Financial Sanction: Asset freeze, transaction prohibitions
# - Travel Ban: Entry restrictions, visa prohibitions
# - Arms Embargo: Weapons trade restrictions
# - Maritime Restriction: Shipping/port access restrictions
#
# == Regime types
#
# Australian sanctions fall into categories:
#
# - UN Security Council: Implemented under UNSC resolutions
#   - 1737 (Iran), 1718 (DPRK), etc.
# - Autonomous: Australia-specific sanctions
#   - Autonomous (Iran), Autonomous (Russia), etc.
# - Country-specific: Targeted at specific nations
#
# == Where each piece lives
#
# One file per definition. The section banners that used to divide the
# single file carried this grouping, and it lives here now:
#
# - Enumerations: entity_type.rb, name_type.rb, alias_strength.rb,
#   script.rb, effect_type.rb
# - Value objects: flexible_date.rb, location.rb
# - Name model: name.rb
# - Sanction model: sanction.rb
# - Entity base class: base_entity.rb
# - Entities: individual.rb, organization.rb, vessel.rb
# - Collection: sanctions_list.rb
#
# @example Loading AU data
#   require 'ammitto/sources/au'
#
#   csv = File.read('Australian_Sanctions_Consolidated_List.csv')
#   list = Ammitto::Sources::Au::SanctionsList.from_csv(csv)
#
#   list.individuals.each do |person|
#     puts person.reference
#     puts person.primary_name
#     puts person.names.map(&:text)
#     puts person.sanction.effects
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
