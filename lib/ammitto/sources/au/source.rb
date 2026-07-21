# frozen_string_literal: true

# AU source models (Lutaml::Model)
require_relative 'sanctions_list'
require_relative 'transformer'

module Ammitto
  module Sources
    module Au
      # Source handles Australia (DFAT) sanctions data
      #
      # Australian sanctions are published by the Department of Foreign
      # Affairs and Trade (DFAT).
      #
      # @example
      #   source = Ammitto::Sources::Au::Source.new
      #   data = source.load_data
      #   results = source.search("Putin", data)
      #
      class Source < BaseSource
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
    end
  end
end

# Register the source
Ammitto::Registry.register(:au, Ammitto::Sources::Au::Source)
