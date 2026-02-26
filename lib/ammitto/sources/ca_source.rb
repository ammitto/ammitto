# frozen_string_literal: true

# CA source models (Lutaml::Model)
require_relative 'ca/sanctions_list'
require_relative 'ca/transformer'

module Ammitto
  # CaSource handles Canada (SEFO) sanctions data
  #
  # Canadian sanctions are published by Global Affairs Canada
  # under the Special Economic Measures Act.
  #
  # @example
  #   source = CaSource.new
  #   data = source.load_data
  #   results = source.search("Putin", data)
  #
  class CaSource < BaseSource
    # @return [Symbol] the source code
    def code
      :ca
    end

    # @return [Authority] the Canada authority
    def authority
      @authority ||= Authority.find('ca')
    end

    # Get the original Canada API endpoint
    # @return [String] the Canada sanctions list URL
    def original_api_endpoint
      'https://www.international.gc.ca/world-monde/international_relations-relations_internationales/sanctions/index.aspx'
    end
  end

  # Register the source
  Registry.register(:ca, CaSource)
end
