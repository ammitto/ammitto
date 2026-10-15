# frozen_string_literal: true

require_relative 'status_history_model'

module Ammitto
  module Ontology
    module Sanction
      class StatusHistory < StatusHistoryModel
        include ValueObjects::Immutable
      end
    end
  end
end
