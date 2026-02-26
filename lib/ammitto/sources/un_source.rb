# frozen_string_literal: true

# UN source models (Lutaml::Model) - order matters for dependencies
require_relative 'un/value_wrapper'
require_relative 'un/individual_alias'
require_relative 'un/entity_alias'
require_relative 'un/individual_address'
require_relative 'un/entity_address'
require_relative 'un/individual_date_of_birth'
require_relative 'un/individual_place_of_birth'
require_relative 'un/individual_document'
require_relative 'un/nationality'
require_relative 'un/designation'
require_relative 'un/individual'
require_relative 'un/entity'
require_relative 'un/individuals_wrapper'
require_relative 'un/entities_wrapper'
require_relative 'un/consolidated_list'
require_relative 'un/transformer'

module Ammitto
  # UnSource handles United Nations sanctions data
  #
  # UN sanctions are published by the UN Security Council and include
  # consolidated lists from various sanctions committees.
  #
  # @example
  #   source = UnSource.new
  #   data = source.load_data
  #   results = source.search("Kim", data)
  #
  class UnSource < BaseSource
    # @return [Symbol] the source code
    def code
      :un
    end

    # @return [Authority] the UN authority
    def authority
      @authority ||= Authority.find('un')
    end

    # Get the original UN API endpoint
    # @return [String] the UN consolidated list URL
    def original_api_endpoint
      'https://scsanctions.un.org/resources/xml/en/consolidated.xml'
    end
  end

  # Register the source
  Registry.register(:un, UnSource)
end
