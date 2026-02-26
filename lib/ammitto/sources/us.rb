# frozen_string_literal: true

# Load dependencies first (leaf classes before composite classes)
require_relative 'us/program_list'
require_relative 'us/aka'
require_relative 'us/aka_list'
require_relative 'us/address'
require_relative 'us/address_list'
require_relative 'us/id'
require_relative 'us/id_list'
require_relative 'us/date_of_birth_item'
require_relative 'us/date_of_birth_list'
require_relative 'us/place_of_birth_item'
require_relative 'us/place_of_birth_list'
require_relative 'us/sdn_entry'
require_relative 'us/publish_information'
require_relative 'us/sdn_list'
require_relative 'us/transformer'

module Ammitto
  module Sources
    # United States (OFAC) sanctions source models
    #
    # Source: https://www.treasury.gov/ofac/downloads/sdn.xml
    # Format: XML
    module Us
    end
  end
end
