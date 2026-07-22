# frozen_string_literal: true

# UN_VESSELS source models (Lutaml::Model)
require_relative 'sanctions_list'
require_relative 'transformer'

module Ammitto
  module Sources
    module UnVessels
      # Source handles the UN Designated Vessels List (1718 Committee)
      #
      # @example
      #   source = Ammitto::Sources::UnVessels::Source.new
      #   data = source.load_data
      #   results = source.search("name", data)
      #
      class Source < BaseSource
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
          'https://main.un.org/securitycouncil/sanctions/1718'
        end
      end
    end
  end
end

# Register the source
Ammitto::Registry.register(:un_vessels, Ammitto::Sources::UnVessels::Source)
