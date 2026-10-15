# frozen_string_literal: true

require_relative 'entity_link_model'

module Ammitto
  module Ontology
    module ValueObjects
      class EntityLink < EntityLinkModel
        include Immutable
      end
    end
  end
end
