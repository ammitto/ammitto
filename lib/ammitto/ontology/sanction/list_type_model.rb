# frozen_string_literal: true

require 'lutaml/model'
require_relative '../value_objects/immutable'

module Ammitto
  module Ontology
    module Sanction
      # Descriptor of the kind of list an entry sits on (SDN List,
      # Unreliable Entity List, ...)
      #
      # @example
      #   ListType.new(name: "SDN List", category: "blocking")
      #
      class ListTypeModel < Lutaml::Model::Serializable
        # List name
        # @return [String, nil]
        attribute :name, :string

        # Names of the list in other languages, as published
        # @return [Array<String>, nil]
        attribute :localized_name, :string, collection: true

        # List category (blocking, sectoral, debarment, ...)
        # @return [String, nil]
        attribute :category, :string

        # Description of the list
        # @return [String, nil]
        attribute :description, :string

        key_value do
          map :name, to: :name
          map :localized_name, to: :localized_name
          map :category, to: :category
          map :description, to: :description
        end
      end
      private_constant :ListTypeModel
    end
  end
end
