# frozen_string_literal: true

require 'lutaml/model'
require_relative 'location'

module Ammitto
  module Sources
    module Uk
      # Birth details with location information
      #
      # Contains place of birth information (town and country).
      # May have multiple locations.
      #
      class BirthDetails < Lutaml::Model::Serializable
        attribute :locations, Location, collection: true

        xml do
          root 'BirthDetails'
          map_element 'Location', to: :locations
        end

        yaml do
          map 'locations', to: :locations
        end

        # Get primary birth location
        # @return [Location, nil]
        def primary_location
          locations.first
        end
      end
    end
  end
end
