# frozen_string_literal: true

require 'lutaml/model'
require_relative '../types'

module Ammitto
  module Ontology
    module ValueObjects
      # Represents a sanction effect/restriction
      #
      # Sanctions can have multiple effects such as asset freezes,
      # travel bans, trade restrictions, etc.
      #
      # @example Creating a sanction effect
      #   effect = SanctionEffect.new(
      #     effect_type: :asset_freeze,
      #     scope: :full,
      #     description: "All funds and economic resources"
      #   )
      #
      class SanctionEffect < Lutaml::Model::Serializable
        # Type of sanction effect
        # @return [Symbol, String, nil]
        attribute :effect_type, :string

        # Scope of the effect (full, partial, targeted, sectoral)
        # @return [Symbol, String, nil]
        attribute :scope, :string

        # Human-readable description
        # @return [String, nil]
        attribute :description, :string

        # Start date of this effect
        # @return [Date, nil]
        attribute :start_date, :date

        # End date of this effect (if temporary)
        # @return [Date, nil]
        attribute :end_date, :date

        # Check if effect has meaningful content
        # @return [Boolean]
        def present?
          effect_type.present?
        end

        # Get type as normalized symbol
        # @return [Symbol]
        def type_sym
          Types.normalize_effect_type(effect_type)
        end

        # Check if this is an asset freeze
        # @return [Boolean]
        def asset_freeze?
          type_sym == :asset_freeze
        end

        # Check if this is a travel ban
        # @return [Boolean]
        def travel_ban?
          type_sym == :travel_ban
        end

        # Convert to hash for JSON-LD serialization
        # @return [Hash]
        def to_hash
          hash = {}
          hash[:effect_type] = effect_type if effect_type
          hash[:scope] = scope if scope
          hash[:description] = description if description
          hash[:start_date] = start_date.to_s if start_date
          hash[:end_date] = end_date.to_s if end_date
          hash
        end

        # JSON mapping
        json do
          map :effect_type, to: :effect_type
          map :scope, to: :scope
          map :description, to: :description
          map :start_date, to: :start_date
          map :end_date, to: :end_date
        end

        # YAML mapping
        yaml do
          map :effect_type, to: :effect_type
          map :scope, to: :scope
          map :description, to: :description
          map :start_date, to: :start_date
          map :end_date, to: :end_date
        end
      end
    end
  end
end
