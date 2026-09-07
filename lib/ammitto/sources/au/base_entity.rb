# frozen_string_literal: true

require 'lutaml/model'
require_relative 'name'
require_relative 'sanction'

module Ammitto
  module Sources
    module Au
      # The Australian sanctions ontology as a whole, how the denormalized
      # CSV maps onto these objects and what the regimes and effects mean,
      # is in lib/ammitto/sources/au.rb.
      # Base class for all sanctioned entities
      class BaseEntity < Lutaml::Model::Serializable
        attribute :reference, :string # Base reference number
        attribute :entity_type, :string # Serialized to YAML for entity type detection
        attribute :names, Name, collection: true
        attribute :address, :string
        attribute :additional_info, :string
        attribute :sanction, Sanction

        # Parse base reference number (strip suffix letters)
        # "8577" -> "8577", "8577a" -> "8577", "8577bcd" -> "8577"
        def self.parse_base_reference(ref)
          match = ref.to_s.match(/^(\d+)/)
          match ? match[1] : ref.to_s
        end

        def primary_name
          names.find(&:primary?)&.text || names.first&.text
        end

        def original_script_name
          names.find(&:original_script?)&.text
        end

        def aliases
          names.select(&:alias?)
        end

        def strong_aliases
          names.select(&:strong_alias?)
        end

        def weak_aliases
          names.select(&:weak_alias?)
        end

        def add_name(name)
          return if name.nil? || name.text.nil? || name.text.empty?
          return if names.any? { |n| n.text == name.text }

          names << name
        end

        def merge_row(row)
          # Add name variant
          name = Name.from_csv(
            row['Name of Individual or Entity'],
            row['Name Type'],
            row['Alias Strength']
          )
          add_name(name)

          # Update sanction info (should be same for all rows)
          self.sanction ||= build_sanction(row)
        end

        private

        def build_sanction(row)
          Sanction.new(
            listing_information: row['Listing Information'],
            committees: row['Committees'],
            control_date: row['Control Date'],
            instrument: row['Instrument of Designation'],
            targeted_financial_sanction: parse_bool(row['Targeted Financial Sanction']),
            travel_ban: parse_bool(row['Travel Ban']),
            arms_embargo: parse_bool(row['Arms Embargo']),
            maritime_restriction: parse_bool(row['Maritime Restriction'])
          )
        end

        def parse_bool(value)
          value.to_s.upcase == 'TRUE'
        end
      end
    end
  end
end
