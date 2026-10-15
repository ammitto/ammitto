# frozen_string_literal: true

require_relative 'raw_source_data_model'

module Ammitto
  module Ontology
    module ValueObjects
      class RawSourceData < RawSourceDataModel
        include Immutable
      end
    end
  end
end
