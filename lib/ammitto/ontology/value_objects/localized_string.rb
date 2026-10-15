# frozen_string_literal: true

require_relative 'localized_string_model'

module Ammitto
  module Ontology
    module ValueObjects
      class LocalizedString < LocalizedStringModel
        include Immutable
      end
    end
  end
end
