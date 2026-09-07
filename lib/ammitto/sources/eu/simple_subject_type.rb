# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Eu
      # Simple subject type for transformer compatibility
      class SimpleSubjectType < Lutaml::Model::Serializable
        attribute :code, :string

        yaml do
          map 'code', to: :code
        end
      end
    end
  end
end
