# frozen_string_literal: true

module Ammitto
  module Sources
    module Au
      # The Australian sanctions ontology as a whole, how the denormalized
      # CSV maps onto these objects and what the regimes and effects mean,
      # is in lib/ammitto/sources/au.rb.
      # Sanction effect type enumeration
      module EffectType
        TARGETED_FINANCIAL_SANCTION = 'targeted_financial_sanction'
        TRAVEL_BAN = 'travel_ban'
        ARMS_EMBARGO = 'arms_embargo'
        MARITIME_RESTRICTION = 'maritime_restriction'

        # Mapping to Ammitto ontology effect types
        TO_AMMITTO = {
          TARGETED_FINANCIAL_SANCTION => 'asset_freeze',
          TRAVEL_BAN => 'travel_ban',
          ARMS_EMBARGO => 'arms_embargo',
          MARITIME_RESTRICTION => 'sectoral_sanction'
        }.freeze
      end
    end
  end
end
