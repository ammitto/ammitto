# frozen_string_literal: true

require_relative 'legal_citation_model'

module Ammitto
  module Ontology
    module ValueObjects
      class LegalCitation < LegalCitationModel
        include Immutable
      end
    end
  end
end
