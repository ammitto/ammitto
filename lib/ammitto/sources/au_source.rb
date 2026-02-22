# frozen_string_literal: true

# AU source models (Lutaml::Model)
require_relative 'au/sanctions_list'
require_relative 'au/transformer'

module Ammitto
  # AuSource handles Australia (DFAT) sanctions data
  #
  # Australian sanctions are published by the Department of Foreign
  # Affairs and Trade (DFAT).
  #
  # @example
  #   source = AuSource.new
  #   data = source.load_data
  #   results = source.search("Putin", data)
  #
  class AuSource < BaseSource
    # @return [Symbol] the source code
    def code
      :au
    end

    # @return [Authority] the Australia authority
    def authority
      @authority ||= Authority.find('au')
    end

    # Get the original Australia API endpoint
    # @return [String] the DFAT sanctions list URL
    def original_api_endpoint
      'https://www.dfat.gov.au/international-relations/security/sanctions/sanctions-regimes'
    end
  end

  # Register the source
  Registry.register(:au, AuSource)
end
