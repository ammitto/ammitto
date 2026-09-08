# frozen_string_literal: true

require 'lutaml/model'

module Ammitto
  module Sources
    module Uk
      # Birth location (town and country)
      #
      class Location < Lutaml::Model::Serializable
        attribute :town_of_birth, :string
        attribute :country_of_birth, :string

        xml do
          root 'Location'
          map_element 'TownOfBirth', to: :town_of_birth
          map_element 'CountryOfBirth', to: :country_of_birth
        end

        yaml do
          map 'town_of_birth', to: :town_of_birth
          map 'country_of_birth', to: :country_of_birth
        end

        # Format as string
        # @return [String]
        def to_s
          [town_of_birth, country_of_birth].compact.join(', ')
        end
      end
    end
  end
end
