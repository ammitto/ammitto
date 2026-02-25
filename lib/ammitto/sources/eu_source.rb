# frozen_string_literal: true

# EU source models (Lutaml::Model) - order matters for dependencies
require_relative 'eu/regulation_summary'
require_relative 'eu/regulation'
require_relative 'eu/subject_type'
require_relative 'eu/name_alias'
require_relative 'eu/birthdate'
require_relative 'eu/citizenship'
require_relative 'eu/address'
require_relative 'eu/identification'
require_relative 'eu/sanction_entity'
require_relative 'eu/processed_entity'
require_relative 'eu/export'
require_relative 'eu/transformer'

module Ammitto
  # EuSource handles European Union sanctions data
  #
  # EU sanctions are published by the European Commission and include
  # persons, entities, and groups subject to restrictive measures.
  #
  # @example
  #   source = EuSource.new
  #   data = source.load_data
  #   results = source.search("Kim", data)
  #
  class EuSource < BaseSource
    # @return [Symbol] the source code
    def code
      :eu
    end

    # @return [Authority] the EU authority
    def authority
      @authority ||= Authority.find('eu')
    end

    # Get the original EU API endpoint
    # @return [String] the EU sanctions list URL
    def original_api_endpoint
      'https://webgate.ec.europa.eu/fsd/fsf/public/files/xmlFullSanctionsList_1_1/content'
    end
  end

  # Register the source
  Registry.register(:eu, EuSource)
end
