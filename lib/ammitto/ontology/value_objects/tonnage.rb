# frozen_string_literal: true

require_relative 'tonnage_model'

module Ammitto
  module Ontology
    module ValueObjects
      class Tonnage < TonnageModel
        include Immutable
      end
    end
  end
end
