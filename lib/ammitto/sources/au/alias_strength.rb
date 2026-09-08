# frozen_string_literal: true

module Ammitto
  module Sources
    module Au
      # The Australian sanctions ontology as a whole, how the denormalized
      # CSV maps onto these objects and what the regimes and effects mean,
      # is in lib/ammitto/sources/au.rb.
      # Alias strength enumeration
      module AliasStrength
        STRONG = 'Strong'
        WEAK = 'Weak'

        ALL = [STRONG, WEAK].freeze

        def self.from_csv(value)
          return nil if value.nil? || value.empty?
          return value if ALL.include?(value)

          case value.downcase
          when 'strong'
            STRONG
          when 'weak'
            WEAK
          else
            value
          end
        end
      end
    end
  end
end
