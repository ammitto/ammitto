# frozen_string_literal: true

# Load dependencies first (leaf classes before composite classes)
require_relative 'eu/regulation_summary'
require_relative 'eu/regulation'
require_relative 'eu/name_alias'
require_relative 'eu/subject_type'
require_relative 'eu/birthdate'
require_relative 'eu/citizenship'
require_relative 'eu/address'
require_relative 'eu/identification'
require_relative 'eu/sanction_entity'
require_relative 'eu/export'
require_relative 'eu/transformer'

module Ammitto
  module Sources
    # European Union sanctions source models
    #
    # Source: https://webgate.ec.europa.eu/fsd/fsf/public/files/xmlFullSanctionsList_1_1/content
    # Format: XML
    module Eu
    end
  end
end
