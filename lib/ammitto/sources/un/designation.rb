# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Un
      # Designation with multiple VALUE elements
      class Designation < Lutaml::Model::Serializable
        attribute :values, :string, collection: true, transform: {
          import: ->(vals) { Array(vals).map { |v| v.to_s.strip.gsub(/\s+/, ' ') } }
        }

        xml do
          root 'DESIGNATION'
          map_element 'VALUE', to: :values
        end

        yaml do
          map 'values', to: :values
        end
      end
    end
  end
end
