# frozen_string_literal: true

# TR source models (Lutaml::Model)
require_relative 'sanctions_list'
require_relative 'transformer'

module Ammitto
  module Sources
    module Tr
      # Source handles the Turkey (Ministry of Treasury and Finance) sanctions list
      #
      # @example
      #   source = Ammitto::Sources::Tr::Source.new
      #   data = source.load_data
      #   results = source.search("name", data)
      #
      class Source < BaseSource
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
          'https://en.hmb.gov.tr/5madde_ing'
        end
      end
    end
  end
end

# Register the source
Ammitto::Registry.register(:tr, Ammitto::Sources::Tr::Source)
