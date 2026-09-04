# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Ch
      # Name part in Swiss sanctions list (given-name, family-name, etc.)
      class NamePart < Lutaml::Model::Serializable
        attribute :order, :integer
        attribute :name_part_type, :string
        attribute :value, :string

        xml do
          root 'name-part'
          map_attribute 'order', to: :order
          map_attribute 'name-part-type', to: :name_part_type
          map_element 'value', to: :value
        end

        yaml do
          map 'order', to: :order
          map 'name_part_type', to: :name_part_type
          map 'value', to: :value
        end
      end
    end
  end
end
