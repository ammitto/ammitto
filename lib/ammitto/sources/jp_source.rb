# frozen_string_literal: true

# JP source models (Lutaml::Model)
require_relative 'jp/sanctions_list'
require_relative 'jp/transformer'

# Ammitto top-level namespace
module Ammitto
  # JpSource handles Japan (MOFA) sanctions data (dormant: PDF source)
  #
  # @example
  #   source = JpSource.new
  #   data = source.load_data
  #   results = source.search("name", data)
  #
  class JpSource < BaseSource
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
      'https://www.mofa.go.jp/'
    end
  end

  # Register the source
  Registry.register(:jp, JpSource)
end
