# frozen_string_literal: true

# UN source models (Lutaml::Model) - order matters for dependencies
require_relative 'value_wrapper'
require_relative 'individual_alias'
require_relative 'entity_alias'
require_relative 'individual_address'
require_relative 'entity_address'
require_relative 'individual_date_of_birth'
require_relative 'individual_place_of_birth'
require_relative 'individual_document'
require_relative 'nationality'
require_relative 'designation'
require_relative 'individual'
require_relative 'entity'
require_relative 'individuals_wrapper'
require_relative 'entities_wrapper'
require_relative 'consolidated_list'
require_relative 'transformer'

module Ammitto
  module Sources
    module Un
      # Source handles United Nations sanctions data
      #
      # UN sanctions are published by the UN Security Council and include
      # consolidated lists from various sanctions committees.
      #
      # @example
      #   source = Ammitto::Sources::Un::Source.new
      #   data = source.load_data
      #   results = source.search("Kim", data)
      #
      class Source < BaseSource
        # @return [Symbol] the source code
        def code
          :un
        end

        # @return [Authority] the UN authority
        def authority
          @authority ||= Authority.find('un')
        end

        # Get the original UN API endpoint
        # @return [String] the UN consolidated list URL
        def original_api_endpoint
          'https://scsanctions.un.org/resources/xml/en/consolidated.xml'
        end
      end
    end
  end
end

# Register the source
Ammitto::Registry.register(:un, Ammitto::Sources::Un::Source)
