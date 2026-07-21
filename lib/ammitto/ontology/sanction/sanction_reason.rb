# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Ontology
    module Sanction
      # Represents the reason for a sanction
      #
      # SanctionReason documents why an entity was sanctioned,
      # including the category of violation and any cited legal provisions.
      #
      # @example Creating a sanction reason
      #   reason = SanctionReason.new(
      #     category: "proliferation",
      #     description: "Involved in nuclear proliferation activities",
      #     cited_provisions: ["UNSCR 1718 (2006)", "UNSCR 1874 (2009)"]
      #   )
      #
      class SanctionReason < Lutaml::Model::Serializable
        # Categories of sanctions reasons
        # @return [Array<String>]
        CATEGORIES = %w[
          terrorism
          proliferation
          human_rights_violations
          corruption
          cyber_activities
          election_interference
          aggression
          procurement_violation
          money_laundering
          drug_trafficking
          transnational_organized_crime
          destabilizing_activity
          sanctions_evasion
          national_security
        ].freeze

        # Category of the sanction reason
        # @return [String, nil]
        attribute :category, :string

        # Detailed description of the reason
        # @return [String, nil]
        attribute :description, :string

        # Legal provisions cited as basis for the sanction
        # @return [Array<String>, nil]
        attribute :cited_provisions, :string, collection: true

        # Check if reason has meaningful content
        # @return [Boolean]
        def present?
          category.present? || description.present?
        end

        # Get category as normalized symbol
        # @return [Symbol, nil]
        def category_sym
          return nil unless category

          normalized = category.to_s.downcase.gsub(/[-\s]+/, '_')
          CATEGORIES.include?(normalized) ? normalized.to_sym : nil
        end

        # Check if this is a terrorism-related reason
        # @return [Boolean]
        def terrorism?
          category_sym == :terrorism
        end

        # Check if this is a proliferation-related reason
        # @return [Boolean]
        def proliferation?
          category_sym == :proliferation
        end

        # Check if this is a human rights violation
        # @return [Boolean]
        def human_rights?
          category_sym == :human_rights_violations
        end

        # Get display string
        # @return [String]
        def to_s
          category&.humanize || description || 'Unknown reason'
        end

        # Convert to hash for JSON-LD serialization
        # @return [Hash]
        def to_hash
          hash = {}
          hash[:category] = category if category
          hash[:description] = description if description
          hash[:cited_provisions] = cited_provisions if cited_provisions&.any?
          hash
        end

        # JSON mapping
        json do
          map 'category', to: :category
          map 'description', to: :description
          map 'citedProvisions', to: :cited_provisions
        end

        # YAML mapping
        yaml do
          map 'category', to: :category
          map 'description', to: :description
          map 'cited_provisions', to: :cited_provisions
        end
      end
    end
  end
end
