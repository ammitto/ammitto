# frozen_string_literal: true

require_relative 'sanction_period_modification_model'

module Ammitto
  module Ontology
    module Sanction
      class SanctionPeriodModification < SanctionPeriodModificationModel
        include ValueObjects::Immutable
      end
    end
  end
end
