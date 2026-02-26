# frozen_string_literal: true

# US source models (Lutaml::Model) - order matters for dependencies
require_relative 'us/publish_information'
require_relative 'us/aka'
require_relative 'us/aka_list'
require_relative 'us/address'
require_relative 'us/address_list'
require_relative 'us/id'
require_relative 'us/id_list'
require_relative 'us/date_of_birth_item'
require_relative 'us/date_of_birth_list'
require_relative 'us/place_of_birth_item'
require_relative 'us/place_of_birth_list'
require_relative 'us/program_list'
require_relative 'us/sdn_entry'
require_relative 'us/sdn_list'
require_relative 'us/transformer'

module Ammitto
  # UsSource handles United States (OFAC) sanctions data
  #
  # US sanctions are published by the Office of Foreign Assets Control (OFAC)
  # and include the Specially Designated Nationals (SDN) list and others.
  #
  # @example
  #   source = UsSource.new
  #   data = source.load_data
  #   results = source.search("Kim", data)
  #
  class UsSource < BaseSource
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

  # Register the source
  Registry.register(:us, UsSource)
end
