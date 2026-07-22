# frozen_string_literal: true

# UN_VESSELS source models (Lutaml::Model)
require_relative 'un_vessels/sanctions_list'
require_relative 'un_vessels/transformer'

# Ammitto top-level namespace
module Ammitto
  # UnVesselsSource handles UN vessels sanctions data (dormant: PDF source)
  #
  # @example
  #   source = UnVesselsSource.new
  #   data = source.load_data
  #   results = source.search("name", data)
  #
  class UnVesselsSource < BaseSource
    # @return [Symbol] the source code
    def code
      :un_vessels
    end

    # @return [Authority] the issuing authority
    def authority
      @authority ||= Authority.find('un_vessels')
    end

    # Get the original source endpoint
    # @return [String] the official source URL
    def original_api_endpoint
      'https://scsanctions.un.org/'
    end
  end

  # Register the source
  Registry.register(:un_vessels, UnVesselsSource)
end
