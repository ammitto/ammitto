# frozen_string_literal: true

require 'lutaml/model'
require_relative 'sanctions_program'
require_relative 'target'

module Ammitto
  module Sources
    module Ch
      # Swiss SECO Sanctions List (XML)
      #
      # The XML has two main sections:
      # - sanctions-program: regime information
      # - target: sanctioned individuals and entities
      #
      class SanctionsList < Lutaml::Model::Serializable
        attribute :list_type, :string
        attribute :date, :string
        attribute :programs, SanctionsProgram, collection: true
        attribute :targets, Target, collection: true

        xml do
          root 'swiss-sanctions-list'
          map_attribute 'list-type', to: :list_type
          map_attribute 'date', to: :date
          map_element 'sanctions-program', to: :programs
          map_element 'target', to: :targets
        end

        yaml do
          map 'list_type', to: :list_type
          map 'date', to: :date
          map 'programs', to: :programs
          map 'targets', to: :targets
        end

        # Get all identities for YAML output
        # @return [Array<Target>]
        def all_identities
          targets
        end

        # Get all individuals
        # @return [Array<Target>]
        def individuals
          targets.select(&:individual)
        end

        # Get all entities (organizations)
        # @return [Array<Target>]
        def entities
          targets.select(&:entity)
        end
      end
    end
  end
end
