# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Eu
      # Simple name alias for transformer compatibility
      class SimpleNameAlias < Lutaml::Model::Serializable
        attribute :whole_name, :string
        attribute :first_name, :string
        attribute :middle_name, :string
        attribute :last_name, :string
        attribute :gender, :string

        yaml do
          map 'whole_name', to: :whole_name
        end
      end
    end
  end
end
