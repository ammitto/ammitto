# frozen_string_literal: true

# JP source models (Lutaml::Model)
require_relative 'entity'
require_relative 'sanctions_list'
require_relative 'transformer'

module Ammitto
  module Sources
    module Jp
      # Source handles the Japan End-User List (METI)
      #
      # @example
      #   source = Ammitto::Sources::Jp::Source.new
      #   data = source.load_data
      #   results = source.search("name", data)
      #
      class Source < BaseSource
        # @return [Symbol] the source code
        def code
          :jp
        end

        # @return [Authority] the issuing authority
        def authority
          @authority ||= Authority.find('jp')
        end

        # Get the original source endpoint
        # @return [String] the official source URL
        def original_api_endpoint
          'https://www.meti.go.jp/policy/anpo/english/law/doc/EndUserListE.html'
        end
      end
    end
  end
end

# Register the source
Ammitto::Registry.register(:jp, Ammitto::Sources::Jp::Source)
