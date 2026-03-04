# frozen_string_literal: true

# EU source models (Lutaml::Model) - order matters for dependencies
require_relative 'regulation_summary'
require_relative 'regulation'
require_relative 'subject_type'
require_relative 'name_alias'
require_relative 'birthdate'
require_relative 'citizenship'
require_relative 'address'
require_relative 'identification'
require_relative 'sanction_entity'
require_relative 'processed_entity'
require_relative 'export'
require_relative 'transformer'

module Ammitto
  module Sources
    module Eu
      # Source handles European Union sanctions data
      #
      # EU sanctions are published by the European Commission and include
      # persons, entities, and groups subject to restrictive measures.
      #
      # @example
      #   source = Ammitto::Sources::Eu::Source.new
      #   data = source.load_data
      #   results = source.search("Kim", data)
      #
      class Source < BaseSource
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
    end
  end
end

# Register the source
Ammitto::Registry.register(:eu, Ammitto::Sources::Eu::Source)
