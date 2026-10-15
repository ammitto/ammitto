# frozen_string_literal: true

require 'lutaml/model'
require_relative 'immutable'

module Ammitto
  module Ontology
    module ValueObjects
      # Represents a temporal period for sanctions
      #
      # Tracks dates for listing, effectiveness, and expiry.
      #
      # @example Creating a temporal period
      #   period = TemporalPeriod.new(
      #     listed_date: Date.new(2022, 3, 15),
      #     effective_date: Date.new(2022, 3, 16),
      #     expiry_date: nil,
      #     is_indefinite: true
      #   )
      #
      class TemporalPeriodModel < Lutaml::Model::Serializable
        # Date when entity was listed
        # @return [Date, nil]
        attribute :listed_date, :date

        # Time of listing as the source wrote it (HH:MM, possibly with a
        # zone); a Date cannot carry it
        # @return [String, nil]
        attribute :listed_time, :string

        # Date when sanctions became effective
        # @return [Date, nil]
        attribute :effective_date, :date

        # Time the sanctions became effective, as the source wrote it
        # @return [String, nil]
        attribute :effective_time, :string

        # Date when sanctions expire (nil if indefinite)
        # @return [Date, nil]
        attribute :expiry_date, :date

        # Whether sanctions are indefinite
        # @return [Boolean]
        attribute :is_indefinite, :boolean, default: false

        # Date of last update
        # @return [Date, nil]
        attribute :last_updated, :date

        # Last-update timestamp exactly as the source wrote it (ISO 8601,
        # time and zone included). Casting it to last_updated would drop
        # both, so the raw value has its own field.
        # @return [String, nil]
        attribute :last_updated_timestamp, :string

        # Check if sanctions are currently active
        # @param as_of [Date] date to check against (default: today)
        # @return [Boolean]
        def active?(as_of: Date.today)
          return false if expiry_date && expiry_date < as_of
          return false if effective_date && effective_date > as_of

          true
        end

        # Check if sanctions are expired
        # @param as_of [Date] date to check against (default: today)
        # @return [Boolean]
        def expired?(as_of: Date.today)
          expiry_date && expiry_date < as_of
        end

        # Get duration in days (nil if indefinite or missing dates)
        # @return [Integer, nil]
        def duration_days
          return nil unless effective_date && expiry_date

          (expiry_date - effective_date).to_i
        end

        # Convert to hash for JSON-LD serialization
        # @return [Hash]
        def to_hash
          hash = {}
          hash[:listed_date] = listed_date.to_s if listed_date
          hash[:listed_time] = listed_time if listed_time
          hash[:effective_date] = effective_date.to_s if effective_date
          hash[:effective_time] = effective_time if effective_time
          hash[:expiry_date] = expiry_date.to_s if expiry_date
          hash[:is_indefinite] = is_indefinite if is_indefinite
          hash[:last_updated] = last_updated.to_s if last_updated
          hash[:last_updated_timestamp] = last_updated_timestamp if last_updated_timestamp
          hash
        end

        # JSON mapping
        json do
          map :listed_date, to: :listed_date
          map :listed_time, to: :listed_time
          map :effective_date, to: :effective_date
          map :effective_time, to: :effective_time
          map :expiry_date, to: :expiry_date
          map :is_indefinite, to: :is_indefinite
          map :last_updated, to: :last_updated
          map :last_updated_timestamp, to: :last_updated_timestamp
        end

        # YAML mapping
        yaml do
          map :listed_date, to: :listed_date
          map :listed_time, to: :listed_time
          map :effective_date, to: :effective_date
          map :effective_time, to: :effective_time
          map :expiry_date, to: :expiry_date
          map :is_indefinite, to: :is_indefinite
          map :last_updated, to: :last_updated
          map :last_updated_timestamp, to: :last_updated_timestamp
        end
      end
      private_constant :TemporalPeriodModel

      class TemporalPeriod < TemporalPeriodModel
        include Immutable
      end
    end
  end
end
