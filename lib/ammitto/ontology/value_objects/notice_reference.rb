# frozen_string_literal: true

require_relative 'notice_reference_model'

module Ammitto
  module Ontology
    module ValueObjects
      class NoticeReference < NoticeReferenceModel
        include Immutable
      end
    end
  end
end
