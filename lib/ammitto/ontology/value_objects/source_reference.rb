# frozen_string_literal: true

require_relative 'source_reference_model'

module Ammitto
  module Ontology
    module ValueObjects
      class SourceReference < SourceReferenceModel
        include Immutable
      end
    end
  end
end
