# frozen_string_literal: true

# NZ source models (Lutaml::Model)
require_relative 'sanctions_list'
require_relative 'transformer'

module Ammitto
  module Sources
    module Nz
      # Source handles New Zealand (MFAT) sanctions data
      #
      # @example
      #   source = Ammitto::Sources::Nz::Source.new
      #   data = source.load_data
      #   results = source.search("name", data)
      #
      class Source < BaseSource
        # @return [Symbol] the source code
        def code
          :nz
        end

        # @return [Authority] the issuing authority
        def authority
          @authority ||= Authority.find('nz')
        end

        # Get the original source endpoint
        # @return [String] the official source URL
        def original_api_endpoint
          'https://www.mfat.govt.nz/en/countries-and-regions/europe/ukraine/russian-invasion-of-ukraine/sanctions/'
        end
      end
    end
  end
end

# Register the source
Ammitto::Registry.register(:nz, Ammitto::Sources::Nz::Source)
