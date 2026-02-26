# frozen_string_literal: true

# CH source models (Lutaml::Model)
require_relative 'ch/sanctions_list'
require_relative 'ch/transformer'

module Ammitto
  # ChSource handles Switzerland (SECO) sanctions data
  #
  # Swiss sanctions are published by the State Secretariat for
  # Economic Affairs (SECO).
  #
  # @example
  #   source = ChSource.new
  #   data = source.load_data
  #   results = source.search("Putin", data)
  #
  class ChSource < BaseSource
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
      'https://www.seco.admin.ch/seco/en/home/Aussenwirtschaft_Warenhandel_aussenwirtschaft_wirtschaft-zusammenarbeit/exportkontrolle-und-sanktionen/sanktionen-embargos.html'
    end
  end

  # Register the source
  Registry.register(:ch, ChSource)
end
