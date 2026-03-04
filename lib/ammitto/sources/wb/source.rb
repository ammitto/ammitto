# frozen_string_literal: true

# WB source models (Lutaml::Model) - order matters for dependencies
require_relative 'sanctioned_firm'
require_relative 'response'
require_relative 'transformer'

module Ammitto
  module Sources
    module Wb
      # Source handles World Bank debarment data
      #
      # World Bank publishes a list of debarred firms and individuals
      # who are ineligible to receive Bank-financed contracts.
      #
      # @example
      #   source = Ammitto::Sources::Wb::Source.new
      #   data = source.load_data
      #   results = source.search("Company", data)
      #
      class Source < BaseSource
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
    end
  end
end

# Register the source
Ammitto::Registry.register(:wb, Ammitto::Sources::Wb::Source)
