# frozen_string_literal: true

module Ammitto
  module Sources
    module Au
      # The Australian sanctions ontology as a whole, how the denormalized
      # CSV maps onto these objects and what the regimes and effects mean,
      # is in lib/ammitto/sources/au.rb.
      # Entity type enumeration
      module EntityType
        INDIVIDUAL = 'Individual'
        ORGANIZATION = 'Entity' # NOTE: CSV uses "Entity" not "Organization"
        VESSEL = 'Vessel'

        ALL = [INDIVIDUAL, ORGANIZATION, VESSEL].freeze

        def self.from_csv(value)
          return nil if value.nil? || value.empty?
          return value if ALL.include?(value)

          # Fallback mapping
          case value.downcase
          when 'individual', 'person'
            INDIVIDUAL
          when 'entity', 'organization', 'company'
            ORGANIZATION
          when 'vessel', 'ship'
            VESSEL
          else
            value
          end
        end
      end
    end
  end
end
