# frozen_string_literal: true

require_relative 'sanction_reason_model'

module Ammitto
  module Ontology
    module Sanction
      class SanctionReason < SanctionReasonModel
        include ValueObjects::Immutable
      end
    end
  end
end
