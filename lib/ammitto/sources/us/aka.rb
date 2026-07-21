# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Us
      # AKA (also known as) entry
      class Aka < Lutaml::Model::Serializable
        attribute :uid, :string
        attribute :type, :string
        attribute :category, :string
        attribute :last_name, :string
        attribute :first_name, :string

        xml do
          root 'aka'
          map_element 'uid', to: :uid
          map_element 'type', to: :type
          map_element 'category', to: :category
          map_element 'lastName', to: :last_name
          map_element 'firstName', to: :first_name
        end

        yaml do
          map 'uid', to: :uid
          map 'type', to: :type
          map 'category', to: :category
          map 'last_name', to: :last_name
          map 'first_name', to: :first_name
        end

        def full_name
          [first_name, last_name].compact.join(' ')
        end
      end
    end
  end
end
