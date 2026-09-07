# frozen_string_literal: true

module Ammitto
  module Sources
    module Au
      # The Australian sanctions ontology as a whole, how the denormalized
      # CSV maps onto these objects and what the regimes and effects mean,
      # is in lib/ammitto/sources/au.rb.
      # Name type enumeration
      module NameType
        PRIMARY = 'Primary Name'
        ORIGINAL_SCRIPT = 'Original Script'
        ALIAS = 'Alias'

        ALL = [PRIMARY, ORIGINAL_SCRIPT, ALIAS].freeze

        def self.from_csv(value)
          return nil if value.nil? || value.empty?

          value
        end
      end
    end
  end
end
