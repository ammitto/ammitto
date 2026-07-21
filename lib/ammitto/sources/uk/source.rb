# frozen_string_literal: true

# UK source models (Lutaml::Model) - order matters for dependencies
require_relative 'name'
require_relative 'non_latin_name'
require_relative 'address'
require_relative 'individual_details'
require_relative 'sanctions_indicators'
require_relative 'designation'
require_relative 'designations'
require_relative 'transformer'

module Ammitto
  module Sources
    module Uk
      # Source handles United Kingdom (OFSI) sanctions data
      #
      # UK sanctions are published by the Office of Financial Sanctions
      # Implementation (OFSI) under the Sanctions Act 2018.
      #
      # @example
      #   source = Ammitto::Sources::Uk::Source.new
      #   data = source.load_data
      #   results = source.search("Putin", data)
      #
      class Source < BaseSource
        # @return [Symbol] the source code
        def code
          :uk
        end

        # @return [Authority] the UK authority
        def authority
          @authority ||= Authority.find('uk')
        end

        # Get the original UK API endpoint
        # @return [String] the UK sanctions list URL
        def original_api_endpoint
          'https://www.gov.uk/government/publications/financial-sanctions-consolidated-list-of-targets'
        end
      end
    end
  end
end

# Register the source
Ammitto::Registry.register(:uk, Ammitto::Sources::Uk::Source)
