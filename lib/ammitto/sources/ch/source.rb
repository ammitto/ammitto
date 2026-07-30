# frozen_string_literal: true

# CH source models (Lutaml::Model)
require_relative 'sanctions_list'
require_relative 'transformer'

module Ammitto
  module Sources
    module Ch
      # Source handles Switzerland (SECO) sanctions data
      #
      # Swiss sanctions are published by the State Secretariat for
      # Economic Affairs (SECO).
      #
      # @example
      #   source = Ammitto::Sources::Ch::Source.new
      #   data = source.load_data
      #   results = source.search("Putin", data)
      #
      class Source < BaseSource
        # @return [Symbol] the source code
        def code
          :ch
        end

        # @return [Authority] the Switzerland authority
        def authority
          @authority ||= Authority.find('ch')
        end

        # Get the original Switzerland API endpoint
        # @return [String] the SECO sanctions list URL
        def original_api_endpoint
          'https://www.seco.admin.ch/en/searching-for-subjects-sanctions'
        end
      end
    end
  end
end

# Register the source
Ammitto::Registry.register(:ch, Ammitto::Sources::Ch::Source)
