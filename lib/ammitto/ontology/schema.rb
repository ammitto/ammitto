# frozen_string_literal: true

module Ammitto
  module Ontology
    # Schema module provides schema context for Ammitto
    module Schema
      # Schema context information
      class Context
        # @return [String] the context URL
        CONTEXT_URL = 'https://ammitto.org/schema/v1/context.jsonld'

        # Get the context URL
        # @return [String]
        def self.context_url
          CONTEXT_URL
        end

        # Get the ontology namespace
        # @return [String]
        def self.ontology_namespace
          'https://www.ammitto.org/ontology/'
        end

        # Get the vocabulary namespace
        # @return [String]
        def self.vocabulary_namespace
          'https://www.ammitto.org/vocab/'
        end
      end
    end
  end
end
