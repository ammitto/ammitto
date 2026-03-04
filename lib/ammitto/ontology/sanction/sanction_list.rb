# frozen_string_literal: true

require 'lutaml/model'
require_relative 'authority'
require_relative 'sanction_regime'
require_relative '../value_objects/localized_string'
require_relative '../value_objects/legal_citation'

module Ammitto
  module Ontology
    module Sanction
      # Represents a sanctions regime/list maintained by an authority
      #
      # SanctionList represents a specific list of sanctioned entities
      # maintained by an authority. Examples include the EU Consolidated List,
      # US OFAC SDN List, China Unreliable Entity List, etc.
      #
      # @example Creating a China Unreliable Entity List
      #   list = SanctionList.new(
      #     id: "https://www.ammitto.org/list/cn/UEL",
      #     source: "cn",
      #     code: "UEL",
      #     name: [
      #       LocalizedString.new(value: "不可靠实体清单", language: "zh", is_primary: true),
      #       LocalizedString.new(value: "Unreliable Entity List", language: "en")
      #     ],
      #     authority: Authority.new(id: "cn", name: "Ministry of Commerce of China"),
      #     list_type: "primary",
      #     status: "active",
      #     established_date: Date.new(2020, 9, 19)
      #   )
      #
      class SanctionList < Lutaml::Model::Serializable
        # Unique IRI identifier
        # @return [String, nil]
        attribute :id, :string

        # Source code (cn, eu, un, us, uk, etc.)
        # @return [String, nil]
        attribute :source, :string

        # List code (e.g., "UEL" for Unreliable Entity List, "ASL" for Anti-Sanction List)
        # @return [String, nil]
        attribute :code, :string

        # Name of the list (multilingual)
        # @return [Array<LocalizedString>, nil]
        attribute :name, ValueObjects::LocalizedString, collection: true

        # Description of the list (multilingual)
        # @return [Array<LocalizedString>, nil]
        attribute :description, ValueObjects::LocalizedString, collection: true

        # Authority that maintains this list
        # @return [Authority, nil]
        attribute :authority, Authority

        # Sanction regime this list belongs to
        # @return [SanctionRegime, nil]
        attribute :regime, SanctionRegime

        # Legal citations establishing this list
        # @return [Array<LegalCitation>, nil]
        attribute :legal_citations, ValueObjects::LegalCitation, collection: true

        # Type of list (primary, secondary, consolidated)
        # @return [String, nil]
        attribute :list_type, :string

        # Current status (active, inactive, archived)
        # @return [String]
        attribute :status, :string, default: 'active'

        # Date when the list was established
        # @return [Date, nil]
        attribute :established_date, :date

        # Official URL for the list
        # @return [String, nil]
        attribute :url, :string

        # Additional metadata
        # @return [Hash, nil]
        attribute :metadata, :hash

        # Check if list is active
        # @return [Boolean]
        def active?
          status == 'active'
        end

        # Check if list is inactive
        # @return [Boolean]
        def inactive?
          status == 'inactive'
        end

        # Get primary name (first name with is_primary=true, or first name)
        # @return [LocalizedString, nil]
        def primary_name
          name&.find(&:primary?) || name&.first
        end

        # Get name in a specific language
        # @param lang [String] language code
        # @return [LocalizedString, nil]
        def name_in_language(lang)
          name&.find { |n| n.language == lang }
        end

        # Get all legal basis citations
        # @return [Array<LegalCitation>]
        def legal_basis_citations
          legal_citations&.select(&:legal_basis?) || []
        end

        key_value do
          map :id, to: :id
          map :source, to: :source
          map :code, to: :code
          map :name, to: :name
          map :description, to: :description
          map :authority, to: :authority
          map :regime, to: :regime
          map :legal_citations, to: :legal_citations
          map :list_type, to: :list_type
          map :status, to: :status
          map :established_date, to: :established_date
          map :url, to: :url
          map :metadata, to: :metadata
        end
      end
    end
  end
end
