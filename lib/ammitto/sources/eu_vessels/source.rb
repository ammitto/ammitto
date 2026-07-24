# frozen_string_literal: true

# EU_VESSELS source models (Lutaml::Model)
require_relative 'sanctions_list'
require_relative 'transformer'

module Ammitto
  module Sources
    module EuVessels
      # Source handles the EU Designated Vessels list (via Denmark DMA)
      #
      # @example
      #   source = Ammitto::Sources::EuVessels::Source.new
      #   data = source.load_data
      #   results = source.search("name", data)
      #
      class Source < BaseSource
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
          'https://www.dma.dk/growth-and-framework-conditions/maritime-sanctions/sanctions-against-russia-and-belarus/eu-vessel-designations'
        end
      end
    end
  end
end

# Register the source
Ammitto::Registry.register(:eu_vessels, Ammitto::Sources::EuVessels::Source)
