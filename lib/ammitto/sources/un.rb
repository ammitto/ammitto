# frozen_string_literal: true

# Load dependencies first (leaf classes before composite classes)
require_relative 'un/value_wrapper'
require_relative 'un/nationality'
require_relative 'un/designation'
require_relative 'un/individual_alias'
require_relative 'un/entity_alias'
require_relative 'un/individual_address'
require_relative 'un/entity_address'
require_relative 'un/individual_date_of_birth'
require_relative 'un/individual_place_of_birth'
require_relative 'un/individual_document'
require_relative 'un/individual'
require_relative 'un/entity'
require_relative 'un/individuals_wrapper'
require_relative 'un/entities_wrapper'
require_relative 'un/consolidated_list'
require_relative 'un/transformer'

module Ammitto
  module Sources
    # United Nations sanctions source models
    #
    # Source: https://scsanctions.un.org/resources/xml/en/consolidated.xml
    # Format: XML
    module Un
    end
  end
end
