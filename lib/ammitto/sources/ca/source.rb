# frozen_string_literal: true

# CA source models (Lutaml::Model)
require_relative 'sanctions_list'
require_relative 'transformer'

module Ammitto
  module Sources
    module Ca
      # Source handles Canada (SEFO) sanctions data
      #
      # Canadian sanctions are published by Global Affairs Canada
      # under the Special Economic Measures Act.
      #
      # @example
      #   source = Ammitto::Sources::Ca::Source.new
      #   data = source.load_data
      #   results = source.search("Putin", data)
      #
      class Source < BaseSource
        # @return [Symbol] the source code
        def code
          :ca
        end

        # @return [Authority] the Canada authority
        def authority
          @authority ||= Authority.find('ca')
        end

        # Get the original Canada API endpoint
        # @return [String] the Canada sanctions list URL
        def original_api_endpoint
          'https://www.international.gc.ca/world-monde/international_relations-relations_internationales/sanctions/index.aspx'
        end
      end
    end
  end
end

# Register the source
Ammitto::Registry.register(:ca, Ammitto::Sources::Ca::Source)
