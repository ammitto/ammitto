# frozen_string_literal: true

# TR source models (Lutaml::Model)
require_relative 'tr/sanctions_list'
require_relative 'tr/transformer'

# Ammitto top-level namespace
module Ammitto
  # TrSource handles Turkey (Ministry of Interior) sanctions data
  #
  # @example
  #   source = TrSource.new
  #   data = source.load_data
  #   results = source.search("name", data)
  #
  class TrSource < BaseSource
    # @return [Symbol] the source code
    def code
      :tr
    end

    # @return [Authority] the issuing authority
    def authority
      @authority ||= Authority.find('tr')
    end

    # Get the original source endpoint
    # @return [String] the official source URL
    def original_api_endpoint
      'https://www.icisleri.gov.tr/'
    end
  end

  # Register the source
  Registry.register(:tr, TrSource)
end
