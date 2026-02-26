# frozen_string_literal: true

# Sanction classes for the Ammitto Sanctions Ontology
#
# These classes represent the sanction-specific aspects of the data,
# including authorities, regimes, entries, reasons, and status history.

require_relative 'sanction/authority'
require_relative 'sanction/sanction_regime'
require_relative 'sanction/sanction_reason'
require_relative 'sanction/sanction_entry'
require_relative 'sanction/status_history'

module Ammitto
  module Ontology
    # Namespace for all sanction-related classes
    module Sanction
    end
  end
end
