# frozen_string_literal: true

# Sanction classes for the Ammitto Sanctions Ontology
#
# These classes represent the sanction-specific aspects of the data,
# including authorities, regimes, entries, and status history.

require_relative 'authority'
require_relative 'sanction_regime'
require_relative 'sanction_entry'
require_relative 'status_history'

module Ammitto
  module Ontology
    # Namespace for all sanction-related classes
    module Sanction
    end
  end
end
