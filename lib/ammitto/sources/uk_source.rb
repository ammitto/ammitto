# frozen_string_literal: true

# UK source models (Lutaml::Model) - order matters for dependencies
require_relative 'uk/name'
require_relative 'uk/non_latin_name'
require_relative 'uk/address'
require_relative 'uk/individual_details'
require_relative 'uk/sanctions_indicators'
require_relative 'uk/designation'
require_relative 'uk/designations'
require_relative 'uk/transformer'

module Ammitto
  # UkSource handles United Kingdom (OFSI) sanctions data
  #
  # UK sanctions are published by the Office of Financial Sanctions
  # Implementation (OFSI) under the Sanctions Act 2018.
  #
  # @example
  #   source = UkSource.new
  #   data = source.load_data
  #   results = source.search("Putin", data)
  #
  class UkSource < BaseSource
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

  # Register the source
  Registry.register(:uk, UkSource)
end
