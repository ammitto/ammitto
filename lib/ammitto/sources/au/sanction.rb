# frozen_string_literal: true

require 'lutaml/model'
require_relative 'effect_type'

module Ammitto
  module Sources
    module Au
      # The Australian sanctions ontology as a whole, how the denormalized
      # CSV maps onto these objects and what the regimes and effects mean,
      # is in lib/ammitto/sources/au.rb.
      # Sanction measures imposed on an entity
      class Sanction < Lutaml::Model::Serializable
        attribute :listing_information, :string
        attribute :committees, :string           # UN committee or regime
        attribute :control_date, :string         # Date added to list
        attribute :instrument, :string           # Legal instrument
        attribute :targeted_financial_sanction, :boolean
        attribute :travel_ban, :boolean
        attribute :arms_embargo, :boolean
        attribute :maritime_restriction, :boolean

        def effects
          effects = []
          effects << EffectType::TARGETED_FINANCIAL_SANCTION if targeted_financial_sanction
          effects << EffectType::TRAVEL_BAN if travel_ban
          effects << EffectType::ARMS_EMBARGO if arms_embargo
          effects << EffectType::MARITIME_RESTRICTION if maritime_restriction
          effects
        end

        def has_effects?
          effects.any?
        end

        def regime_type
          return nil if committees.nil? || committees.empty?

          # Parse regime type from committees field
          if committees.include?('Autonomous')
            :autonomous
          elsif committees.match?(/\d{4}/)
            :un_security_council
          else
            :other
          end
        end

        def to_ammitto_effect_types
          effects.map { |e| EffectType::TO_AMMITTO[e] }.compact
        end
      end
    end
  end
end
