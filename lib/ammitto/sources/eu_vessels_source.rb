# frozen_string_literal: true

# EU_VESSELS source models (Lutaml::Model)
require_relative 'eu_vessels/sanctions_list'
require_relative 'eu_vessels/transformer'

# Ammitto top-level namespace
module Ammitto
  # EuVesselsSource handles EU vessels sanctions data
  #
  # @example
  #   source = EuVesselsSource.new
  #   data = source.load_data
  #   results = source.search("name", data)
  #
  class EuVesselsSource < BaseSource
    # @return [Symbol] the source code
    def code
      :eu_vessels
    end

    # @return [Authority] the issuing authority
    def authority
      @authority ||= Authority.find('eu_vessels')
    end

    # Get the original source endpoint
    # @return [String] the official source URL
    def original_api_endpoint
      'https://webgate.ec.europa.eu/fsd/fsf'
    end
  end

  # Register the source
  Registry.register(:eu_vessels, EuVesselsSource)
end
