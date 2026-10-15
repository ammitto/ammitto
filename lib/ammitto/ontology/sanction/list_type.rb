# frozen_string_literal: true

require_relative 'list_type_model'

module Ammitto
  module Ontology
    module Sanction
      class ListType < ListTypeModel
        include ValueObjects::Immutable
      end
    end
  end
end
