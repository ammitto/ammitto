# frozen_string_literal: true

# WB source models (Lutaml::Model) - order matters for dependencies
require_relative 'wb/sanctioned_firm'
require_relative 'wb/response'
require_relative 'wb/transformer'

module Ammitto
  # WbSource handles World Bank debarment data
  #
  # World Bank publishes a list of debarred firms and individuals
  # who are ineligible to receive Bank-financed contracts.
  #
  # @example
  #   source = WbSource.new
  #   data = source.load_data
  #   results = source.search("Company", data)
  #
  class WbSource < BaseSource
    # @return [Symbol] the source code
    def code
      :wb
    end

    # @return [Authority] the World Bank authority
    def authority
      @authority ||= Authority.find('wb')
    end

    # Get the original World Bank API endpoint
    # @return [String] the World Bank debarment list URL
    def original_api_endpoint
      'https://apigwext.worldbank.org/dvsvc/v1.0/json/SP.TransactionalDebarment_GetList'
    end
  end

  # Register the source
  Registry.register(:wb, WbSource)
end
