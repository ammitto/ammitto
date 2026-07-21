# frozen_string_literal: true

# US source models (Lutaml::Model) - order matters for dependencies
require_relative 'publish_information'
require_relative 'aka'
require_relative 'aka_list'
require_relative 'address'
require_relative 'address_list'
require_relative 'id'
require_relative 'id_list'
require_relative 'date_of_birth_item'
require_relative 'date_of_birth_list'
require_relative 'place_of_birth_item'
require_relative 'place_of_birth_list'
require_relative 'program_list'
require_relative 'sdn_entry'
require_relative 'sdn_list'
require_relative 'transformer'

module Ammitto
  module Sources
    module Us
      # Source handles United States (OFAC) sanctions data
      #
      # US sanctions are published by the Office of Foreign Assets Control (OFAC)
      # and include the Specially Designated Nationals (SDN) list and others.
      #
      # @example
      #   source = Ammitto::Sources::Us::Source.new
      #   data = source.load_data
      #   results = source.search("Kim", data)
      #
      class Source < BaseSource
        # @return [Symbol] the source code
        def code
          :us
        end

        # @return [Authority] the US authority
        def authority
          @authority ||= Authority.find('us')
        end

        # Get the original OFAC API endpoint
        # @return [String] the OFAC SDN list URL
        def original_api_endpoint
          'https://www.treasury.gov/ofac/downloads/sdn.xml'
        end
      end
    end
  end
end

# Register the source
Ammitto::Registry.register(:us, Ammitto::Sources::Us::Source)
